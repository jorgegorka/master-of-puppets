require "test_helper"

class MessagesCreatedAtIndexTest < ActiveSupport::TestCase
  test "messages has an index on created_at for dashboard rollup queries" do
    indexes = ActiveRecord::Base.connection.indexes(:messages).map(&:name)
    assert_includes indexes, "index_messages_on_created_at",
                    "expected index_messages_on_created_at for dashboard rollup queries; got #{indexes.inspect}"
  end
end
