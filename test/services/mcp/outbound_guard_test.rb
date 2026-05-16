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
    with_singleton_method(Resolv, :getaddresses, ->(_h) { ["169.254.169.254"] }) do
      err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("http://meta") }
      assert_match(/cloud metadata/, err.message)
    end
  end

  test "RFC1918 ranges are denied by default" do
    with_singleton_method(Resolv, :getaddresses, ->(_h) { ["10.0.0.5"] }) do
      err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("http://internal") }
      assert_match(/private range/, err.message)
    end
  end

  test "RFC1918 ranges are allowed with MOP_MCP_ALLOW_PRIVATE=1" do
    ENV["MOP_MCP_ALLOW_PRIVATE"] = "1"
    with_singleton_method(Resolv, :getaddresses, ->(_h) { ["10.0.0.5"] }) do
      assert_equal "10.0.0.5", Mcp::OutboundGuard.allowed!("http://internal")
    end
  end

  test "public IPs are allowed and the resolved IP is returned for pinning" do
    with_singleton_method(Resolv, :getaddresses, ->(_h) { ["93.184.216.34"] }) do
      assert_equal "93.184.216.34", Mcp::OutboundGuard.allowed!("https://example.com")
    end
  end

  test "dual-stack record with one metadata IP is denied" do
    with_singleton_method(Resolv, :getaddresses, ->(_h) { ["93.184.216.34", "169.254.169.254"] }) do
      err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("https://example.com") }
      assert_match(/cloud metadata/, err.message)
    end
  end

  test "empty resolution is denied" do
    with_singleton_method(Resolv, :getaddresses, ->(_h) { [] }) do
      err = assert_raises(RuntimeError) { Mcp::OutboundGuard.allowed!("http://nx.example") }
      assert_match(/did not resolve/, err.message)
    end
  end
end
