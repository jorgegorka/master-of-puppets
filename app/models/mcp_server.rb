class McpServer < ApplicationRecord
  include Eventable
  include Enableable
  include Discoverable

  belongs_to :user
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
end
