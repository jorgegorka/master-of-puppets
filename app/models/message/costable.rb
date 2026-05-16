module Message::Costable
  extend ActiveSupport::Concern

  def compute_cost
    Llm::Pricing.compute(
      provider:              provider,
      model:                 model,
      prompt_tokens:         prompt_tokens,
      completion_tokens:     completion_tokens,
      cache_read_tokens:     cache_read_tokens,
      cache_creation_tokens: cache_creation_tokens
    )
  rescue Llm::Pricing::UnknownModel
    0
  end

  def total_tokens
    prompt_tokens.to_i + completion_tokens.to_i
  end
end
