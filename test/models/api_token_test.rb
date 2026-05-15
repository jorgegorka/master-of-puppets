require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "create_with_secret returns plaintext only once" do
    record, raw = ApiToken.create_with_secret!(user: users(:one), name: "cli")
    assert raw.include?(".")
    prefix, _ = raw.split(".", 2)
    assert_equal record.prefix, prefix
  end

  test "authenticate matches valid token" do
    _, raw = ApiToken.create_with_secret!(user: users(:one), name: "cli")
    assert ApiToken.authenticate(raw)
    refute ApiToken.authenticate(raw + "x")
    refute ApiToken.authenticate("bogus")
    refute ApiToken.authenticate(nil)
  end

  test "default user is Current.user" do
    Current.user = users(:one)
    token = ApiToken.create!(name: "cli", prefix: "abc12345", token: "x" * 32)
    assert_equal users(:one), token.user
  end
end
