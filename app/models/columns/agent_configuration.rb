module Columns
  module AgentConfiguration
    extend ActiveSupport::Concern

    included do
      validate :validate_adapter_config_schema, if: :agent?
      before_validation :filter_adapter_config, if: :adapter_config_changed?
    end

    def adapter_class
      return nil if adapter_type.blank?
      AdapterRegistry.for(adapter_type)
    end

    private

    def filter_adapter_config
      return if adapter_type.blank?
      allowed = AdapterRegistry.all_config_keys(adapter_type).map(&:to_s)
      self.adapter_config = (adapter_config || {}).stringify_keys.slice(*allowed)
    rescue ArgumentError
      # unknown adapter type — leave adapter_config alone, validation will fail it
    end

    def validate_adapter_config_schema
      return if adapter_type.blank?
      required_keys = AdapterRegistry.required_config_keys(adapter_type)
      missing = required_keys - (adapter_config || {}).keys.map(&:to_s)
      if missing.any?
        errors.add(:adapter_config, "missing required keys: #{missing.join(', ')}")
      end
    rescue ArgumentError => e
      errors.add(:adapter_type, e.message)
    end
  end
end
