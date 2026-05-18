require "test_helper"

module Llm
  class ClientTest < ActiveSupport::TestCase
    test "returns Anthropic adapter for anthropic provider" do
      provider_configs(:anthropic).update!(api_key: "test")
      adapter = Llm::Client.for(provider: "anthropic")
      assert_kind_of Llm::Anthropic, adapter
    end

    test "returns OpenAi adapter for openai provider" do
      provider_configs(:openai).update!(api_key: "test")
      adapter = Llm::Client.for(provider: "openai")
      assert_kind_of Llm::OpenAi, adapter
    end

    test "raises for unknown provider" do
      ProviderConfig.create!(provider: "bogus", default_model: "x", base_url: "https://x")
      assert_raises(ArgumentError) { Llm::Client.for(provider: "bogus") }
    end
  end
end
