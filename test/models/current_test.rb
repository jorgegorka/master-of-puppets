require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test "stores user and session attributes" do
    fake = Struct.new(:email).new("a@b.com")
    Current.user = fake
    assert_equal "a@b.com", Current.user.email
  end

  test "exposes ip_address and user_agent attributes" do
    Current.ip_address = "127.0.0.1"
    Current.user_agent = "Capybara/test"
    assert_equal "127.0.0.1", Current.ip_address
    assert_equal "Capybara/test", Current.user_agent
  end
end
