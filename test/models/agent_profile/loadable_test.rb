require "test_helper"

class AgentProfile::LoadableTest < ActiveSupport::TestCase
  test "refresh_from_yaml! upserts each profile + tracks events" do
    Current.user = users(:one)
    AgentProfile.delete_all
    assert_difference -> { AgentProfile.count }, 2 do
      AgentProfile.refresh_from_yaml!
    end
    backend = AgentProfile.find_by!(slug: "backend")
    assert_equal "Backend Worker", backend.display_name
    assert_includes backend.specialties, "Rails"
    assert_predicate backend, :enabled?
  end

  test "refresh_from_yaml! is idempotent — second call writes no rows" do
    Current.user = users(:one)
    AgentProfile.delete_all
    AgentProfile.refresh_from_yaml!
    assert_no_difference -> { AgentProfile.count } do
      AgentProfile.refresh_from_yaml!
    end
    assert_no_difference -> { Event.where(action: "agent_profile_updated").count } do
      AgentProfile.refresh_from_yaml!
    end
  end
end
