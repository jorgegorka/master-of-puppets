require "ipaddr"
require "resolv"

module Mcp
  # SSRF guard for outbound MCP HTTP requests. Blocks cloud-metadata IPs
  # outright; blocks RFC1918 / loopback / link-local by default unless
  # MOP_MCP_ALLOW_PRIVATE=1 (covers self-hosted MCP servers on the LAN
  # during dev, like a context7 instance behind a tailnet).
  class OutboundGuard
    DENYLIST = %w[169.254.169.254 169.254.170.2].freeze
    PRIVATE_RANGES = [
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10")
    ].freeze

    def self.allowed!(url)
      uri = URI.parse(url.to_s)
      raise "denied: non-http(s) scheme #{uri.scheme.inspect}" unless %w[http https].include?(uri.scheme)
      raise "denied: missing host" unless uri.host

      address = Resolv.getaddress(uri.host)
      raise "denied: cloud metadata IP #{address}" if DENYLIST.include?(address)

      ip = IPAddr.new(address)
      private_match = PRIVATE_RANGES.any? { |range| range.include?(ip) }
      if private_match && ENV["MOP_MCP_ALLOW_PRIVATE"] != "1"
        raise "denied: #{address} is in a private range — set MOP_MCP_ALLOW_PRIVATE=1 to override"
      end

      true
    end
  end
end
