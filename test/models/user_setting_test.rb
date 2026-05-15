require "test_helper"

class UserSettingTest < ActiveSupport::TestCase
  test "auto-created when user is created" do
    user = User.create!(email: "freshly@b.com", password: "supersecret123")
    assert user.user_setting.present?
    assert_equal "claude-official", user.user_setting.theme
    assert_equal "indigo", user.user_setting.accent
  end

  test "theme is required" do
    setting = UserSetting.new(user: users(:one), theme: "", accent: "indigo")
    refute setting.valid?
    assert_includes setting.errors[:theme], "can't be blank"
  end
end
