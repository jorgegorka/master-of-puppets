require "test_helper"

module Llm
  class PricingTest < ActiveSupport::TestCase
    test "compute applies rate to tokens per million" do
      cost = Llm::Pricing.compute(
        provider: "anthropic",
        model:    "claude-opus-4-7",
        prompt_tokens:     1_000_000,
        completion_tokens: 0
      )
      assert_in_delta 15.0, cost, 0.0001
    end

    test "unknown model raises" do
      assert_raises(Llm::Pricing::UnknownModel) do
        Llm::Pricing.compute(provider: "anthropic", model: "ghost", prompt_tokens: 100, completion_tokens: 10)
      end
    end

    test "models_for returns model ids in TABLE order for a known provider" do
      assert_equal %w[claude-opus-4-7 claude-sonnet-4-6 claude-haiku-4-5],
                   Llm::Pricing.models_for("anthropic")
    end

    test "models_for returns [] for unknown provider" do
      assert_equal [], Llm::Pricing.models_for("nope")
    end

    test "TABLE is deep-frozen" do
      assert Llm::Pricing::TABLE.frozen?
      assert Llm::Pricing::TABLE["anthropic"].frozen?
      assert Llm::Pricing::TABLE.dig("anthropic", "claude-opus-4-7").frozen?
      assert_raises(FrozenError) do
        Llm::Pricing::TABLE["anthropic"]["claude-opus-4-7"][:input] = 0
      end
    end
  end
end
