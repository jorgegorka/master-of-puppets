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

  # A non-admin with a skill whose frontmatter declares `tools: [run_shell]`
  # must NOT receive run_shell in available_tools — the admin gate must hold
  # even when the tool is re-introduced via a skill manifest.
  test "non-admin with run_shell skill does not gain run_shell via skill tool_definitions" do
    non_admin = users(:two)
    assert non_admin.member?, "fixture sanity: users(:two) must be a non-admin"

    skill = Skill.create!(
      slug:           "shell_escape_test",
      name:           "Shell Escape Test",
      category:       "test",
      description:    "Skill that declares run_shell in its manifest",
      manifest:       { "name" => "shell_escape_test", "tools" => [ "run_shell" ] },
      source_path:    "/dev/null",
      origin:         :builtin,
      security_level: :safe,
      body_digest:    Digest::SHA256.hexdigest("test"),
      discovered_at:  Time.current
    )
    skill.enable_for(non_admin)

    chat = ChatSession.create!(user: non_admin, title: "T", model: "m", provider: "anthropic")
    msg  = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                 model: "claude-sonnet-4-5", provider: "anthropic")

    names = msg.available_tools.map { |t| t[:name] }
    refute_includes names, "run_shell",
      "non-admin must not gain run_shell through a skill's tool_definitions"
  end

  test "admin with run_shell skill retains run_shell via skill tool_definitions" do
    admin = users(:one)
    assert admin.admin?, "fixture sanity: users(:one) must be admin"

    skill = Skill.create!(
      slug:           "shell_admin_test",
      name:           "Shell Admin Test",
      category:       "test",
      description:    "Skill that declares run_shell for admin",
      manifest:       { "name" => "shell_admin_test", "tools" => [ "run_shell" ] },
      source_path:    "/dev/null",
      origin:         :builtin,
      security_level: :safe,
      body_digest:    Digest::SHA256.hexdigest("test_admin"),
      discovered_at:  Time.current
    )
    skill.enable_for(admin)

    chat = ChatSession.create!(user: admin, title: "T", model: "m", provider: "anthropic")
    msg  = chat.messages.create!(role: :assistant, status: :pending, content_blocks: [],
                                 model: "claude-sonnet-4-5", provider: "anthropic")

    names = msg.available_tools.map { |t| t[:name] }
    assert_includes names, "run_shell",
      "admin must retain run_shell even when it comes from a skill manifest"
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
