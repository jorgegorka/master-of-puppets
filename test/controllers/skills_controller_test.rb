require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user   = users(:one)    # admin
    @member = users(:member)
    sign_in_as(@user)
    @skill = skills(:filesystem)
  end

  test "index renders" do
    get skills_path
    assert_response :success
    assert_match @skill.name, response.body
  end

  test "index filters by search query" do
    @skill.reindex_fts!
    get skills_path, params: { q: "Filesystem" }
    assert_response :success
    assert_match @skill.name, response.body
  end

  test "show renders with security badge" do
    get skill_path(@skill)
    assert_response :success
    assert_match @skill.security_level, response.body
  end

  test "update reloads skill from disk (admin only)" do
    sign_in_as(@member)
    patch skill_path(@skill)
    assert_redirected_to root_path
  end

  test "destroy removes skill (admin only)" do
    sign_in_as(@member)
    delete skill_path(@skill)
    assert_redirected_to root_path
    assert Skill.exists?(@skill.id), "non-admin should not have deleted the skill"
  end

  test "signed-out users are redirected" do
    delete session_path
    get skills_path
    assert_redirected_to new_session_path
  end
end
