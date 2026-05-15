require "test_helper"

class Message::AdvanceJobTest < ActiveJob::TestCase
  test "advance_later enqueues" do
    message = messages(:hello)
    assert_enqueued_with(job: Message::AdvanceJob, args: [ message ]) do
      message.advance_later
    end
  end

  test "captures Current.user at enqueue" do
    user = users(:one)
    Current.user = user
    job = Message::AdvanceJob.new(messages(:hello))
    assert_equal user, job.captured_user
  end

  test "Current.user round-trips through serialize/deserialize" do
    user = users(:one)
    Current.user = user
    job = Message::AdvanceJob.new(messages(:hello))
    payload = job.serialize
    assert_equal user.to_global_id.to_s, payload["captured_user"]

    revived = Message::AdvanceJob.new
    revived.deserialize(payload)
    assert_equal user.id, revived.captured_user&.id
  end
end
