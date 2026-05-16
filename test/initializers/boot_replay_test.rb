require "test_helper"

class BootReplayLeaderTest < ActiveSupport::TestCase
  teardown { ENV.delete("PUMA_WORKER_INDEX") }

  test "leader? is true when PUMA_WORKER_INDEX is unset (single-mode Puma)" do
    ENV.delete("PUMA_WORKER_INDEX")
    assert BootReplayLeader.leader?
  end

  test "leader? is true for worker 0" do
    ENV["PUMA_WORKER_INDEX"] = "0"
    assert BootReplayLeader.leader?
  end

  test "leader? is false for non-zero workers" do
    ENV["PUMA_WORKER_INDEX"] = "1"
    assert_not BootReplayLeader.leader?
    ENV["PUMA_WORKER_INDEX"] = "5"
    assert_not BootReplayLeader.leader?
  end
end

class BootReplayInitializerWiringTest < ActiveSupport::TestCase
  # The actual after_initialize block in each initializer is skipped under
  # Rails.env.test?, so we can't exercise it end-to-end here without
  # invasive monkey-patching. Instead, verify that both initializers reference
  # BootReplayLeader.leader? so the gate stays in place across refactors.

  test "agents_supervisor_client initializer gates on BootReplayLeader.leader?" do
    source = Rails.root.join("config/initializers/agents_supervisor_client.rb").read
    assert_includes source, "BootReplayLeader.leader?"
  end

  test "workspace_bootstrap initializer gates on BootReplayLeader.leader?" do
    source = Rails.root.join("config/initializers/workspace_bootstrap.rb").read
    assert_includes source, "BootReplayLeader.leader?"
  end
end
