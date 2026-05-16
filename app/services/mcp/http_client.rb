require "faraday"

module Mcp
  # JSON-RPC over HTTP client for MCP servers. SSRF-guarded; bearer / basic
  # auth materializes from the (encrypted) auth_payload at request time —
  # never logged. Bubble Faraday + JSON errors up to the caller; McpServer
  # and McpTool both rescue them into the right shape (status flip /
  # Tool::Result.failure).
  class HttpClient
    DEFAULT_TIMEOUT     = Integer(ENV.fetch("MOP_MCP_HTTP_TIMEOUT", 10))
    MAX_RESPONSE_BYTES  = Integer(ENV.fetch("MOP_MCP_MAX_RESPONSE_BYTES", 4 * 1024 * 1024))

    def initialize(server)
      @server    = server
      @pinned_ip = OutboundGuard.allowed!(server.url)
      @conn      = build_connection
    end

    def list_tools
      json_rpc("tools/list").fetch("tools", []).map do |t|
        {
          name:         t.fetch("name"),
          description:  t["description"].to_s,
          input_schema: t["inputSchema"] || t["input_schema"] || {}
        }
      end
    end

    def call_tool(name, input)
      result = json_rpc("tools/call", name: name, arguments: input)
      # The MCP protocol returns content blocks; tests/callers want a string,
      # so collapse them into a single payload while preserving structure if
      # it's already a string.
      case result
      when Hash    then result["content"] || result.to_json
      when Array   then result.map { |b| b["text"] || b.to_json }.join("\n")
      else result.to_s
      end
    end

    def ping
      json_rpc("ping")
      true
    end

    private
      def build_connection
        pinned_ip = @pinned_ip
        Faraday.new(url: @server.url) do |f|
          f.request :json
          f.response :json, content_type: /\bjson$/
          f.options.timeout      = DEFAULT_TIMEOUT
          f.options.open_timeout = DEFAULT_TIMEOUT
          f.headers["User-Agent"] = "master-of-puppets/phase-4"
          apply_auth(f)
          # Pin to the IP we already vetted in OutboundGuard so Net::HTTP can't
          # re-resolve to a different (e.g. 169.254.169.254) record between the
          # check and the connect. Hostname is preserved for SNI and certificate
          # verification.
          f.adapter :net_http do |http|
            http.ipaddr = pinned_ip if pinned_ip
          end
        end
      end

      def apply_auth(faraday)
        case @server.auth_type
        when "bearer"
          token = @server.auth_credentials["token"]
          faraday.request :authorization, "Bearer", token if token.present?
        when "basic"
          creds = @server.auth_credentials
          faraday.request :authorization, :basic, creds["username"], creds["password"]
        end
      end

      def json_rpc(method, params = {})
        body     = { jsonrpc: "2.0", id: SecureRandom.hex(4), method: method, params: params }
        response = @conn.post("", body)
        raise "MCP #{method} HTTP #{response.status}" unless response.success?

        # Defense against a hostile or misconfigured MCP server returning a
        # huge body. The Content-Length advisory bails before we touch the
        # parsed body; the ObjectSpace check on the parsed payload catches
        # under-reported / streaming responses. Net::HTTP buffers the body
        # before Faraday's :json middleware parses it, so the real OOM-strict
        # bound is the read timeout (MOP_MCP_HTTP_TIMEOUT) × bandwidth.
        declared = response.headers["content-length"]&.to_i
        if declared && declared > MAX_RESPONSE_BYTES
          raise "MCP #{method} response too large: declared #{declared} bytes (cap #{MAX_RESPONSE_BYTES})"
        end
        raw_size = response.body.is_a?(String) ? response.body.bytesize : response.body.to_json.bytesize
        if raw_size > MAX_RESPONSE_BYTES
          raise "MCP #{method} response too large: #{raw_size} bytes (cap #{MAX_RESPONSE_BYTES})"
        end

        if response.body.is_a?(Hash) && response.body["error"]
          raise "MCP #{method} error: #{response.body['error']}"
        end
        response.body.is_a?(Hash) ? response.body["result"] : response.body
      end
  end
end
