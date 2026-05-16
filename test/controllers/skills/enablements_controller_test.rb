require "test_helper"

class Skills::EnablementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @skill = skills(:filesystem)  # safe
  end

  test "create enables a safe skill without install" do
    assert_difference -> { SkillEnablement.count }, 1 do
      post skill_enablement_path(@skill)
    end
    assert_redirected_to skill_path(@skill)
  end

  test "create on medium skill without install shows alert" do
    @skill.update!(security_level: :medium)
    post skill_enablement_path(@skill)
    assert_redirected_to skill_path(@skill)
    assert_match(/requires explicit install_for/, flash[:alert].to_s)
  end

  test "destroy disables the skill" do
    @skill.enable_for(@user)
    assert_difference -> { SkillEnablement.count }, -1 do
      delete skill_enablement_path(@skill)
    end
  end
end
