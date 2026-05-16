require "test_helper"
require "stringio"
require "socket"

class AgentsSupervisor::ClientTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "consume enqueues Memory::IndexerJob per path in a memory.changed notification" do
    payload = {
      jsonrpc: "2.0",
      method:  "memory.changed",
      params:  { paths: [ "a.md", "nested/b.md" ] }
    }.to_json

    assert_enqueued_jobs 2, only: Memory::IndexerJob do
      AgentsSupervisor::Client.new.consume(StringIO.new("#{payload}\n"))
    end

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.last(2)
    assert_equal %w[a.md nested/b.md], enqueued.map { |j| j[:args].first }
  end

  test "consume ignores notifications with other methods" do
    payload = { jsonrpc: "2.0", method: "health.pong", params: {} }.to_json

    assert_no_enqueued_jobs only: Memory::IndexerJob do
      AgentsSupervisor::Client.new.consume(StringIO.new("#{payload}\n"))
    end
  end

  test "consume tolerates malformed JSON lines" do
    bad = "{ this isn't json\n"
    good = { jsonrpc: "2.0", method: "memory.changed", params: { paths: [ "x.md" ] } }.to_json

    assert_enqueued_jobs 1, only: Memory::IndexerJob do
      AgentsSupervisor::Client.new.consume(StringIO.new("#{bad}#{good}\n"))
    end
  end

  test "stop! breaks the consume loop on the next line" do
    client = AgentsSupervisor::Client.new
    payload = { jsonrpc: "2.0", method: "memory.changed", params: { paths: [ "x.md" ] } }.to_json
    socket  = StringIO.new("#{payload}\n#{payload}\n")

    # Flip the flag after the first line is consumed
    queue = ActiveJob::Base.queue_adapter
    queue.singleton_class.alias_method(:__real_enqueue, :enqueue)
    queue.define_singleton_method(:enqueue) do |job|
      client.stop!
      __real_enqueue(job)
    end
    begin
      assert_enqueued_jobs 1, only: Memory::IndexerJob do
        client.consume(socket)
      end
    ensure
      queue.singleton_class.alias_method(:enqueue, :__real_enqueue)
      queue.singleton_class.remove_method(:__real_enqueue)
    end
  end

  test "stop! closes an active socket so a blocked each_line wakes" do
    sock_a, sock_b = UNIXSocket.pair
    client = AgentsSupervisor::Client.new
    client.instance_variable_set(:@socket, sock_a)

    consumer = Thread.new { client.consume(sock_a) }
    # Give the thread time to enter the blocking each_line read on sock_a.
    sleep 0.05

    client.stop!

    assert consumer.join(1), "consume did not unblock within 1s after stop!"
    assert sock_a.closed?, "stop! should have closed the active socket"
  ensure
    sock_a&.close rescue nil
    sock_b&.close rescue nil
  end
end
