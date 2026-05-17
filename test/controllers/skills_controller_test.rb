require "test_helper"

class SkillsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
    @skill.reindex_fts_entry!(slug: @skill.slug, name: @skill.name, category: @skill.category,
                              description: @skill.description.to_s, body: @skill.body)
    get skills_path, params: { q: "Filesystem" }
    assert_response :success
    assert_match @skill.name, response.body
  end

  test "show renders with security badge" do
    get skill_path(@skill)
    assert_response :success
    assert_match @skill.security_level, response.body
  end

  test "update enqueues Skill::ReloadJob with the disk path (admin)" do
    assert_enqueued_with(job: Skill::ReloadJob, args: [ { path: @skill.source_path } ]) do
      patch skill_path(@skill)
    end
    assert_redirected_to @skill
    assert_match(/Reload queued/, flash[:notice])
  end

  test "update is admin-only" do
    sign_in_as(@member)
    assert_no_enqueued_jobs(only: Skill::ReloadJob) do
      patch skill_path(@skill)
    end
    assert_redirected_to root_path
  end

  test "destroy route is not defined any more (U4)" do
    assert_raises(ActionController::UrlGenerationError) do
      url_for(controller: "skills", action: "destroy", id: @skill.id, only_path: true)
    end
  end

  test "signed-out users are redirected" do
    delete session_path
    get skills_path
    assert_redirected_to new_session_path
  end
end
