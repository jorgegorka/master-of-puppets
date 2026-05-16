require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "PATCH /settings.json updates theme + accent and returns 204" do
    patch settings_path(format: :json),
      params:  { user_setting: { theme: "slate", accent: "violet" } }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json" }

    assert_response :no_content
    @user.user_setting.reload
    assert_equal "slate",  @user.user_setting.theme
    assert_equal "violet", @user.user_setting.accent
  end

  test "HTML PATCH /settings still redirects" do
    patch settings_path, params: { user_setting: { theme: "mono", accent: "red" } }
    assert_redirected_to settings_path
    assert_equal "mono", @user.user_setting.reload.theme
  end
end
