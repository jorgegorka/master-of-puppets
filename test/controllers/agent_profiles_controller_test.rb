require "test_helper"

class AgentProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # users(:one) has role: 1 (admin); use it as the admin baseline.
    Current.user = users(:one)
    AgentProfile.refresh_from_yaml!
    sign_in_as users(:one)
  end

  test "index lists rostered profiles" do
    get agent_profiles_path
    assert_response :ok
    assert_match "Backend Worker", response.body
  end

  test "non-admin gets 403" do
    Current.user = users(:two)
    sign_in_as users(:two)
    get agent_profiles_path
    assert_response :forbidden
  end

  test "sync action upserts from YAML" do
    AgentProfile.delete_all
    post agent_profiles_sync_path
    assert_response :redirect
    assert_operator AgentProfile.count, :>, 0
  end
end
