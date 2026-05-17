require "test_helper"

class AgentProfileSkillTest < ActiveSupport::TestCase
  test "join validates uniqueness on (agent_profile, skill)" do
    profile = agent_profiles(:backend)
    skill   = skills(:research)
    AgentProfileSkill.create!(agent_profile: profile, skill: skill)
    dup = AgentProfileSkill.new(agent_profile: profile, skill: skill)
    assert_not dup.valid?
  end

  test "AgentProfile.skills_for(user) intersects profile skills with user enablement" do
    Current.user = users(:one)
    profile = agent_profiles(:backend)
    research_skill = skills(:research)
    build_skill    = skills(:builder)
    profile.skills << research_skill << build_skill

    research_skill.install_for(users(:one))
    research_skill.enable_for(users(:one))
    # builder is installed/enabled for a DIFFERENT user
    build_skill.install_for(users(:two))
    build_skill.enable_for(users(:two))

    assigned = profile.skills_for(users(:one))
    assert_includes assigned, research_skill
    refute_includes assigned, build_skill
  end
end
