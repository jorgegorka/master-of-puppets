class McpServer < ApplicationRecord
  include Eventable
  include Enableable
  include Discoverable

  belongs_to :user, default: -> { Current.user }
  has_many :tools, class_name: "McpTool", dependent: :destroy

  encrypts :env_payload, :auth_payload

  enum :transport_type, { http: 0, sse: 1, stdio: 2 }, prefix: :transport
  enum :auth_type,      { none: 0, bearer: 1, basic: 2 }, prefix: :auth
  enum :tool_mode,      { all: 0, include_list: 1, exclude_list: 2 }, prefix: :tool_mode
  enum :status,         { unknown: 0, reachable: 1, error: 2, disabled: 3 }

  validates :slug, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true
  validates :transport_type, presence: true
  validates :url,              presence: true, if: -> { transport_http? || transport_sse? }
  validates :command_template, presence: true, if: :transport_stdio?

  def env
    JSON.parse(env_payload || "{}")
  rescue JSON::ParserError
    {}
  end

  def auth_credentials
    JSON.parse(auth_payload || "{}")
  rescue JSON::ParserError
    {}
  end

  # Pings the server, flips status, records last_checked_at, and tracks an
  # event in either path. Returns true on reachable, false otherwise — never
  # re-raises, so controllers can pick the flash based on the return value
  # without a rescue arm of their own (and so a stale find can keep raising
  # ActiveRecord::RecordNotFound up to Rails' default 404 handler).
  #
  # The raw exception message goes only to last_error (truncated) and the
  # server log — never to the flash, because Faraday / SSRF errors can leak
  # resolved IPs, internal hostnames, or auth fragments.
  def check_reachability!
    Mcp::HttpClient.new(self).ping
    transaction do
      update!(status: :reachable, last_error: nil, last_checked_at: Time.current)
      track_event :reachability_checked, result: :ok
    end
    true
  rescue StandardError => e
    Rails.logger.warn("[McpServer #{id}] reachability check failed: #{e.class}: #{e.message}")
    transaction do
      update!(status: :error, last_error: e.message.to_s[0, 255], last_checked_at: Time.current)
      track_event :reachability_checked, result: :error, error_class: e.class.name
    end
    false
  end

  def transport_type_options
    self.class.transport_types.keys.map { |k| [ k, k ] }
  end

  def self.transport_type_options
    transport_types.keys.map { |k| [ k, k ] }
  end

  def self.auth_type_options
    auth_types.keys.map { |k| [ k, k ] }
  end

  def self.tool_mode_options
    tool_modes.keys.map { |k| [ k, k ] }
  end
end
