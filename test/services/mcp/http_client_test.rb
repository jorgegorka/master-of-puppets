require "test_helper"
require "support/method_stub"

class Mcp::HttpClientTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:one)
    @server = mcp_servers(:context7_http)
    @url    = @server.url
    # OutboundGuard runs Resolv.getaddresses(host); keep it offline by stubbing
    # to a public-looking address that the guard's RFC1918 list won't match.
    Resolv.singleton_class.alias_method(:__real_getaddresses, :getaddresses)
    Resolv.define_singleton_method(:getaddresses) { |_h| ["93.184.216.34"] }
  end

  teardown do
    Resolv.singleton_class.alias_method(:getaddresses, :__real_getaddresses)
    Resolv.singleton_class.send(:remove_method, :__real_getaddresses)
  end

  test "list_tools returns normalized tool definitions" do
    stub_rpc_response("tools/list", result: {
      "tools" => [
        { "name" => "search", "description" => "Look up docs", "inputSchema" => { "type" => "object" } },
        { "name" => "fetch",  "description" => "Fetch URL",    "input_schema" => { "type" => "object" } }
      ]
    })

    result = Mcp::HttpClient.new(@server).list_tools
    assert_equal 2, result.size
    assert_equal "search", result[0][:name]
    assert_equal({ "type" => "object" }, result[0][:input_schema])
    assert_equal({ "type" => "object" }, result[1][:input_schema])
  end

  test "call_tool collapses Hash content blocks to a string" do
    stub_rpc_response("tools/call", result: { "content" => "answer" })
    assert_equal "answer", Mcp::HttpClient.new(@server).call_tool("search", { query: "ruby" })
  end

  test "call_tool collapses Array content blocks to joined text" do
    stub_rpc_response("tools/call", result: [
      { "type" => "text", "text" => "line 1" },
      { "type" => "text", "text" => "line 2" }
    ])
    assert_equal "line 1\nline 2", Mcp::HttpClient.new(@server).call_tool("search", {})
  end

  test "HTTP non-2xx raises with status code" do
    WebMock.stub_request(:post, @url).to_return(status: 503, body: "")
    err = assert_raises(RuntimeError) { Mcp::HttpClient.new(@server).list_tools }
    assert_match(/HTTP 503/, err.message)
  end

  test "JSON-RPC error envelope raises" do
    stub_rpc_response("tools/list", error: { "code" => -1, "message" => "downstream boom" })
    err = assert_raises(RuntimeError) { Mcp::HttpClient.new(@server).list_tools }
    assert_match(/downstream boom/, err.message)
  end

  test "SSRF guard runs at construction time and blocks private IPs" do
    Resolv.define_singleton_method(:getaddresses) { |_h| ["10.0.0.5"] }
    assert_raises(RuntimeError) { Mcp::HttpClient.new(@server) }
  end

  test "response body over MAX_RESPONSE_BYTES is rejected" do
    cap     = Mcp::HttpClient::MAX_RESPONSE_BYTES
    payload = { jsonrpc: "2.0", id: "x", result: { "tools" => [ { "name" => "x", "description" => "y" * (cap + 1) } ] } }.to_json
    WebMock.stub_request(:post, @url).to_return(
      status:  200,
      headers: { "Content-Type" => "application/json", "Content-Length" => payload.bytesize.to_s },
      body:    payload
    )
    err = assert_raises(RuntimeError) { Mcp::HttpClient.new(@server).list_tools }
    assert_match(/response too large/i, err.message)
  end

  test "declared Content-Length over MAX_RESPONSE_BYTES is rejected even if body is small" do
    # A lying server might advertise a huge length but stream a tiny body. The
    # Content-Length advisory still trips the cap so we never trust a server
    # that has signalled intent to flood.
    WebMock.stub_request(:post, @url).to_return(
      status:  200,
      headers: { "Content-Type" => "application/json", "Content-Length" => ((Mcp::HttpClient::MAX_RESPONSE_BYTES + 1)).to_s },
      body:    { jsonrpc: "2.0", id: "x", result: { "tools" => [] } }.to_json
    )
    err = assert_raises(RuntimeError) { Mcp::HttpClient.new(@server).list_tools }
    assert_match(/response too large/i, err.message)
  end

  test "bearer auth header is injected from auth_payload" do
    @server.update!(auth_type: :bearer, auth_payload: { token: "secret-token" }.to_json)
    body_seen = nil
    WebMock.stub_request(:post, @url).with do |req|
      body_seen = req.headers
      true
    end.to_return(status: 200, headers: { "Content-Type" => "application/json" },
                  body: { jsonrpc: "2.0", id: "x", result: { "tools" => [] } }.to_json)

    Mcp::HttpClient.new(@server).list_tools
    assert_includes body_seen["Authorization"].to_s, "Bearer secret-token"
  end

  private
    def stub_rpc_response(_method, result: nil, error: nil)
      body = if error
        { jsonrpc: "2.0", id: "x", error: error }
      else
        { jsonrpc: "2.0", id: "x", result: result }
      end

      WebMock.stub_request(:post, @url).to_return(
        status:  200,
        headers: { "Content-Type" => "application/json" },
        body:    body.to_json
      )
    end
end
