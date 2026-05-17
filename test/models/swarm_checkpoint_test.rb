require "test_helper"

class SwarmCheckpointTest < ActiveSupport::TestCase
  test ".parse extracts a single checkpoint stanza" do
    raw = <<~RAW
      Just some noise
      ===HERMES CHECKPOINT===
      state_label: planning
      runtime_state:
        step: 1
      files_changed: []
      commands_run: []
      result: "Sketched the API"
      blocker: null
      next_action: "Wire the controller"
      ===END CHECKPOINT===
      more noise
    RAW

    parsed = SwarmCheckpoint.parse(raw)
    assert_equal 1, parsed.size
    cp = parsed.first
    assert_equal "planning", cp[:state_label]
    assert_equal "Sketched the API", cp[:result]
    assert_nil cp[:blocker]
    assert_equal "Wire the controller", cp[:next_action]
    assert_equal({ "step" => 1 }, cp[:runtime_state])
  end

  test ".parse returns [] on no markers" do
    assert_equal [], SwarmCheckpoint.parse("nothing\nhere\n")
  end

  test ".parse skips malformed stanzas without raising" do
    raw = <<~RAW
      ===HERMES CHECKPOINT===
      not: yaml at all
        this is: { broken: [ ]
      ===END CHECKPOINT===
      ===HERMES CHECKPOINT===
      state_label: good
      runtime_state: {}
      files_changed: []
      commands_run: []
      result: "ok"
      blocker: null
      next_action: null
      ===END CHECKPOINT===
    RAW
    parsed = SwarmCheckpoint.parse(raw)
    assert_equal 1, parsed.size
    assert_equal "good", parsed.first[:state_label]
  end

  test ".parse detects blocker stanza" do
    raw = <<~RAW
      ===HERMES CHECKPOINT===
      state_label: stuck
      runtime_state: {}
      files_changed: []
      commands_run: []
      result: null
      blocker: "Need DB credentials"
      next_action: null
      ===END CHECKPOINT===
    RAW
    parsed = SwarmCheckpoint.parse(raw)
    assert_equal "Need DB credentials", parsed.first[:blocker]
  end
end
