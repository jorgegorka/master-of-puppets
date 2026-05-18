require "test_helper"

class Swarm::OutputBufferTest < ActiveSupport::TestCase
  test "consume returns and clears buffered content" do
    buf = Swarm::OutputBuffer.new
    buf.instance_variable_get(:@buffers)[42] << "hello"
    buf.instance_variable_get(:@buffers)[42] << " world"
    assert_equal "hello world", buf.consume(42)
    assert_equal "", buf.consume(42)
  end

  test "enforce_cap evicts oldest bytes" do
    buf = Swarm::OutputBuffer.new
    buf.instance_variable_get(:@buffers)[1] << "x" * (Swarm::OutputBuffer::MAX_BUFFER_BYTES + 100)
    buf.send(:enforce_cap, 1)
    assert_equal Swarm::OutputBuffer::MAX_BUFFER_BYTES, buf.instance_variable_get(:@buffers)[1].bytesize
  end
end
