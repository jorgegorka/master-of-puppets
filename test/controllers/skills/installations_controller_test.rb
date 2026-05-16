require "test_helper"

class Skills::InstallationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @skill = skills(:filesystem)
  end

  test "create installs the skill for the current user" do
    assert_difference -> { SkillInstallation.count }, 1 do
      post skill_installation_path(@skill)
    end
    assert_redirected_to skill_path(@skill)
  end

  test "destroy uninstalls the skill" do
    @skill.install_for(@user)
    assert_difference -> { SkillInstallation.count }, -1 do
      delete skill_installation_path(@skill)
    end
  end
end
