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
  end
end
