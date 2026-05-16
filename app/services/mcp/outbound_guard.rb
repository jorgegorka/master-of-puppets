require "ipaddr"
require "resolv"

module Mcp
  # SSRF guard for outbound MCP HTTP requests. Blocks cloud-metadata IPs
  # outright; blocks RFC1918 / loopback / link-local by default unless
  # MOP_MCP_ALLOW_PRIVATE=1 (covers self-hosted MCP servers on the LAN
  # during dev, like a context7 instance behind a tailnet).
  class OutboundGuard
    # Always-denied IPs. Metadata service endpoints across major clouds — these
    # MUST never be reachable regardless of MOP_MCP_ALLOW_PRIVATE, because the
    # "private LAN" escape hatch is for trusted on-prem services, not for
    # making EC2 IMDS reachable to a malicious MCP host. Stored as IPAddr so
    # comparison is canonical (catches ::ffff:169.254.169.254 → 169.254.169.254).
    METADATA_IPS = [
      IPAddr.new("169.254.169.254"),  # AWS/GCP/Azure IMDSv1+v2 over IPv4
      IPAddr.new("169.254.170.2"),    # AWS ECS task metadata
      IPAddr.new("fd00:ec2::254")     # AWS IMDS over IPv6
    ].freeze

    PRIVATE_RANGES = [
      IPAddr.new("0.0.0.0/8"),        # "this network"; Linux/macOS route 0.0.0.0 to loopback
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("224.0.0.0/4"),      # multicast
      IPAddr.new("255.255.255.255"),  # limited broadcast
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7"),
      IPAddr.new("fe80::/10")
    ].freeze

    # Resolves the hostname once, validates *every* A/AAAA record (a dual-stack
    # host with one safe and one metadata-IP record must not slip through), and
    # returns the resolved IP so the caller can pin it onto the socket — closes
    # the TOCTOU window where Faraday would otherwise re-resolve at connect
    # time and pick up a flipped, low-TTL record.
    def self.allowed!(url)
      uri = URI.parse(url.to_s)
      raise "denied: non-http(s) scheme #{uri.scheme.inspect}" unless %w[http https].include?(uri.scheme)

      host = uri.hostname
      raise "denied: missing host" if host.nil? || host.empty?

      addresses = Resolv.getaddresses(host)
      raise "denied: #{host} did not resolve" if addresses.empty?

      addresses.each do |address|
        ip = canonicalize(address)
        raise "denied: cloud metadata IP #{ip}" if METADATA_IPS.any? { |m| m.include?(ip) }

        private_match = PRIVATE_RANGES.any? { |range| range.include?(ip) }
        if private_match && ENV["MOP_MCP_ALLOW_PRIVATE"] != "1"
          raise "denied: #{ip} is in a private range — set MOP_MCP_ALLOW_PRIVATE=1 to override"
        end
      end

      addresses.first
    end

    # IPAddr.new("127.0.0.0/8").include?(IPAddr.new("::ffff:127.0.0.1")) is false:
    # the v4-mapped v6 form is technically a v6 address. Unwrap it to its
    # native v4 form before any range check so 4-in-6 disguises don't slip
    # past the metadata + private filters.
    def self.canonicalize(address)
      ip = IPAddr.new(address)
      ip.ipv4_mapped? ? ip.native : ip
    end
    private_class_method :canonicalize
  end
end
