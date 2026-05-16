require "application_system_test_case"

class ThemeSwitcherSystemTest < ApplicationSystemTestCase
  test "user picks a theme; it persists on the row and survives a reload" do
    user = User.create!(email: "theme@example.test", password: "supersecret123")
    sign_in(user)

    visit settings_path
    # Stimulus mounts on connect → page-load value matches the user's stored theme.
    assert_match(/^claude-official(-light)?$/, find("html")["data-theme"])

    select "slate", from: "user_setting[theme]"

    # The Stimulus controller does an async fetch; wait for the row to flip.
    Timeout.timeout(2) do
      sleep 0.1 until user.user_setting.reload.theme == "slate"
    end

    visit settings_path
    assert_equal "slate", find("html")["data-theme"]
  end
end
