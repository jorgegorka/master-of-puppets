require "test_helper"

class ScheduledJob::RunnableTest < ActiveSupport::TestCase
  setup do
    @sj = scheduled_jobs(:daily_digest)
  end

  test "run! produces a succeeded JobRun with cost + output captured" do
    adapter = LlmStubs::StubAdapter.new(text: "Hello from scheduled job")

    run = nil
    with_stubbed_llm(adapter) do
      assert_difference -> { JobRun.count }, +1 do
        run = @sj.run!
      end
    end

    assert run.succeeded?, "expected run to be succeeded, was #{run.status}"
    assert_match(/Hello from scheduled job/, run.output)
    assert run.cost_usd.positive?
    assert_equal 12, run.prompt_tokens
    assert_equal 7,  run.completion_tokens
    assert_not_nil run.chat_session
  end

  test "run! advances next_run_at + last_run_at" do
    adapter = LlmStubs::StubAdapter.new(text: "ok")
    before  = @sj.next_run_at

    with_stubbed_llm(adapter) { @sj.run! }
    @sj.reload

    assert_not_equal before, @sj.next_run_at
    assert_not_nil @sj.last_run_at
  end

  test "adapter raises → JobRun is :failed with error_message" do
    adapter = LlmStubs::RaisingAdapter.new(message: "boom")

    run = nil
    with_stubbed_llm(adapter) { run = @sj.run! }

    assert run.failed?, "expected run to be failed, was #{run.status}"
    assert_equal "boom", run.error_message
  end

  test "run! tracks scheduled_job_run_started and scheduled_job_run_succeeded events" do
    adapter = LlmStubs::StubAdapter.new(text: "done")

    with_stubbed_llm(adapter) { @sj.run! }

    actions = @sj.events.pluck(:action)
    assert_includes actions, "scheduled_job_run_started"
    assert_includes actions, "scheduled_job_run_succeeded"
  end

  test "run! truncates output that exceeds MAX_OUTPUT_BYTES" do
    big = "x" * (ScheduledJob::Runnable::MAX_OUTPUT_BYTES + 1024)
    adapter = LlmStubs::StubAdapter.new(text: big)

    run = nil
    with_stubbed_llm(adapter) { run = @sj.run! }

    assert run.succeeded?
    assert run.output.bytesize <= ScheduledJob::Runnable::MAX_OUTPUT_BYTES + 64,
           "output should be truncated near the cap, got #{run.output.bytesize} bytes"
    assert_match(/truncated/, run.output)
  end

  test "run! records original byte size when output is truncated" do
    big = "x" * (ScheduledJob::Runnable::MAX_OUTPUT_BYTES + 1024)
    adapter = LlmStubs::StubAdapter.new(text: big)

    run = nil
    with_stubbed_llm(adapter) { run = @sj.run! }

    assert run.succeeded?
    assert_equal big.bytesize, run.output_truncated_at_bytes,
                 "expected original size #{big.bytesize}, got #{run.output_truncated_at_bytes.inspect}"
  end

  test "run! leaves output_truncated_at_bytes nil when output fits" do
    adapter = LlmStubs::StubAdapter.new(text: "short")

    run = nil
    with_stubbed_llm(adapter) { run = @sj.run! }

    assert run.succeeded?
    assert_nil run.output_truncated_at_bytes
  end
end
