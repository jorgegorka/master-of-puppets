Rails.application.config.after_initialize do
  env_model = ENV["MOP_DEFAULT_MODEL"]
  next if env_model.blank?

  valid_models = Llm::Pricing.models_for("anthropic")
  unless valid_models.include?(env_model)
    raise "MOP_DEFAULT_MODEL=#{env_model.inspect} is not in Llm::Pricing::TABLE['anthropic']: #{valid_models.inspect}"
  end
end
