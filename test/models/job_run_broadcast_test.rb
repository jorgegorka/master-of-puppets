require "test_helper"

class JobRunBroadcastTest < ActionCable::Channel::TestCase
  # Note: `broadcast_replace_to` ultimately calls
  # `ActionCable.server.broadcast(stream_name_from(streamables), …)`, where
  # `stream_name_from` returns the *unsigned* `to_gid_param` (see
  # turbo-rails 2.0.23, app/channels/turbo/streams/broadcasts.rb:103). The
  # signed variant is only used in HTML, not as the cable stream key. So we
  # assert against the unsigned name here.
  test "JobRun status change broadcasts to its ScheduledJob turbo stream" do
    run    = job_runs(:succeeded_one)
    sj     = run.scheduled_job
    stream = sj.to_gid_param

    assert_broadcasts(stream, 1) do
      run.update!(status: :running)
    end
  end
end
