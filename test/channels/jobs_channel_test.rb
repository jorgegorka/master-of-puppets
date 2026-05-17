require "test_helper"

class JobsChannelTest < ActionCable::Channel::TestCase
  test "subscribes to scheduled_job stream when user owns it" do
    stub_connection current_user: users(:one)
    subscribe scheduled_job_id: scheduled_jobs(:daily_digest).id
    assert subscription.confirmed?
    assert_has_stream_for scheduled_jobs(:daily_digest)
  end

  test "rejects cross-tenant subscribe" do
    stub_connection current_user: users(:member)
    subscribe scheduled_job_id: scheduled_jobs(:daily_digest).id
    assert subscription.rejected?
  end
end
