require "test_helper"

class CspTest < ActionDispatch::IntegrationTest
  test "GET / sets the §15.7 CSP" do
    sign_in_as(users(:one))
    get root_path
    csp = response.headers["Content-Security-Policy"]
    assert_not_nil csp, "CSP header should be set"
    assert_match(/default-src 'self'/, csp)
    assert_match(%r{script-src .*'self'.*https://esm\.sh}, csp)
    assert_match(/worker-src .*'self'.*blob:/, csp)
    assert_match(/connect-src .*'self'.*wss:.*ws:/, csp)
    assert_match(/object-src 'none'/, csp)
    assert_match(/frame-ancestors 'none'/, csp)
  end
end
