require "test_helper"

class Dashboard::RollupTest < ActiveSupport::TestCase
  test "tokens_by_day groups completed messages by day" do
    msg = messages(:hello)
    msg.update!(status: :completed, prompt_tokens: 100, completion_tokens: 50, cost_usd: "0.01", created_at: 2.days.ago)
    Message.create!(chat_session: msg.chat_session, role: :assistant, status: :completed,
                    content_blocks: [], model: msg.model, provider: msg.provider,
                    prompt_tokens: 200, completion_tokens: 100, cost_usd: "0.02", created_at: 1.day.ago)

    rollup = Dashboard::Rollup.new(scope: Message.where(chat_session: msg.chat_session))
    days   = rollup.tokens_by_day
    assert_equal 2, days.size
    assert(days.all? { |row| row[:tokens] > 0 && row[:cost_usd].to_f > 0 })
  end

  test "cost_by_model sums per model" do
    Message.create!(chat_session: chat_sessions(:one), role: :assistant, status: :completed,
                    content_blocks: [], model: "claude-haiku-4-5", provider: "anthropic",
                    cost_usd: "0.01")
    Message.create!(chat_session: chat_sessions(:one), role: :assistant, status: :completed,
                    content_blocks: [], model: "claude-opus-4-7", provider: "anthropic",
                    cost_usd: "0.15")

    rollup  = Dashboard::Rollup.new(scope: Message.all)
    by_model = rollup.cost_by_model
    assert_equal BigDecimal("0.15"), by_model["claude-opus-4-7"]
    assert_equal BigDecimal("0.01"), by_model["claude-haiku-4-5"]
  end
end
