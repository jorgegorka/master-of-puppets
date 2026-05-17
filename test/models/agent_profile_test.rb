require "test_helper"

class AgentProfileTest < ActiveSupport::TestCase
  test "validates slug presence + uniqueness" do
    AgentProfile.create!(slug: "qa", display_name: "QA Worker",
                         role: "qa-engineer", model: "claude-sonnet-4-5",
                         provider: "anthropic", cwd: "agents/qa")
    dup = AgentProfile.new(slug: "qa", display_name: "Dup",
                           role: "x", model: "claude-sonnet-4-5",
                           provider: "anthropic", cwd: "agents/dup")
    assert_not dup.valid?
    assert_includes dup.errors[:slug], "has already been taken"
  end

  test "status enum members + default" do
    profile = AgentProfile.new(slug: "p", display_name: "P", role: "r",
                               model: "m", provider: "anthropic", cwd: "p")
    assert_equal "offline", profile.status
    assert_respond_to profile, :online?
    assert_respond_to profile, :away?
    assert_respond_to profile, :offline?
  end

  test "enabled scope and disabled scope partition" do
    enabled  = AgentProfile.create!(slug: "a", display_name: "A", role: "r",
                                    model: "m", provider: "anthropic",
                                    cwd: "a", enabled: true)
    disabled = AgentProfile.create!(slug: "b", display_name: "B", role: "r",
                                    model: "m", provider: "anthropic",
                                    cwd: "b", enabled: false)
    assert_includes AgentProfile.enabled,   enabled
    assert_includes AgentProfile.disabled,  disabled
    refute_includes AgentProfile.enabled,   disabled
  end
end
