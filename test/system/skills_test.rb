require "application_system_test_case"

class SkillsTest < ApplicationSystemTestCase
  setup do
    @user  = users(:one)
    @skill = skills(:filesystem)
  end

  test "user installs and enables a skill via the UI" do
    sign_in(@user)

    visit skills_path
    click_link @skill.name
    click_button "Install"
    assert_text "Installed."
    click_button "Enable"
    assert_text "Enabled."
  end
end
