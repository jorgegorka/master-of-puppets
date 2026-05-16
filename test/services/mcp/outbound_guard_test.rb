require "test_helper"
require "support/method_stub"

class Mcp::OutboundGuardTest < ActiveSupport::TestCase
  teardown { ENV.delete("MOP_MCP_ALLOW_PRIVATE") }

  test "non-http(s) scheme is denied" do
    err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("file:///etc/passwd") }
    assert_match(/non-http\(s\)/, err.message)
  end

  test "missing host is denied" do
    err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("http://") }
    assert_match(/missing host/, err.message)
  end

  test "AWS/GCP metadata IP is denied even with MOP_MCP_ALLOW_PRIVATE=1" do
    ENV["MOP_MCP_ALLOW_PRIVATE"] = "1"
    with_singleton_method(Resolv, :getaddress, ->(_h) { "169.254.169.254" }) do
      err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("http://meta") }
      assert_match(/cloud metadata/, err.message)
    end
  end

  test "RFC1918 ranges are denied by default" do
    with_singleton_method(Resolv, :getaddress, ->(_h) { "10.0.0.5" }) do
      err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("http://internal") }
      assert_match(/private range/, err.message)
    end
  end

  test "RFC1918 ranges are allowed with MOP_MCP_ALLOW_PRIVATE=1" do
    ENV["MOP_MCP_ALLOW_PRIVATE"] = "1"
    with_singleton_method(Resolv, :getaddress, ->(_h) { "10.0.0.5" }) do
      assert Mcp::OutboundGuard.allowed!("http://internal")
    end
  end

  test "public IPs are allowed" do
    with_singleton_method(Resolv, :getaddress, ->(_h) { "93.184.216.34" }) do
      assert Mcp::OutboundGuard.allowed!("https://example.com")
    end
  end
end
