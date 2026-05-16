require "application_system_test_case"

class SkillsTest < ApplicationSystemTestCase
  setup do
    @user  = users(:one)
    @skill = skills(:filesystem)
  end

  test "user installs and enables a skill via the UI" do
    sign_in(@user)

    visit skills_path
    # Trip the assertion if the badge CSS is ever removed — the helper
    # emits `.badge.badge--<variant>` and the system test needs the
    # styles to actually exist for the page to render correctly.
    assert_selector ".badge.badge--ok, .badge.badge--warn, .badge.badge--danger"
    click_link @skill.name
    click_button "Install"
    assert_text "Installed."
    click_button "Enable"
    assert_text "Enabled."
  end
end
