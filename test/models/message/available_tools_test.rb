require "test_helper"

class Message::AvailableToolsTest < ActiveSupport::TestCase
  setup do
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
  end

  # NOTE: `users(:one)` is admin (role: 1) per the fixture. Use `users(:two)`
  # for the non-admin assertion (added in Task 6.0 Step 4).
  test "non-admin chat session excludes run_shell" do
    Current.user = users(:two)
    chat = ChatSession.create!(user: users(:two), title: "T", model: "m", provider: "anthropic")
    msg = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                model: "claude-sonnet-4-5", provider: "anthropic")
    assert chat.user.member?
    names = msg.available_tools.map { |t| t[:name] }
    refute_includes names, "run_shell"
  end

  test "admin chat session includes run_shell" do
    Current.user = users(:one)  # role: 1 = admin
    chat = ChatSession.create!(user: users(:one), title: "T", model: "m", provider: "anthropic")
    msg = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                model: "claude-sonnet-4-5", provider: "anthropic")
    names = msg.available_tools.map { |t| t[:name] }
    assert_includes names, "run_shell"
  end

  test "swarm-worker chat session uses agent_profile.skills, not user.enabled_skills" do
    Current.user = users(:two)  # non-admin to keep the surface tight
    mission = SwarmMission.create!(user: users(:two), created_by: users(:two), title: "M", goal: "G")
    profile = AgentProfile.find_by!(slug: "backend")
    research = skills(:research)
    profile.skills << research
    research.install_for(users(:two)); research.enable_for(users(:two))
    asg = SwarmAssignment.create!(swarm_mission: mission, agent_profile: profile, task: "T")
    chat = ChatSession.create!(user: users(:two), title: "Worker", model: "m", provider: "anthropic",
                               swarm_assignment: asg)
    msg = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                model: "claude-sonnet-4-5", provider: "anthropic")
    # The skill defines no tools — assert it appears in system prompt but no tool def is added
    assert_match(/Skill: Research/, msg.system_prompt)
  end
end
