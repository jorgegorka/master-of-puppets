class Tool::Internal
  # JSON-schema "type" → Ruby class(es) the value must be an instance of.
  TYPE_MAP = {
    "string"  => [ String ],
    "integer" => [ Integer ],
    "number"  => [ Numeric ],
    "boolean" => [ TrueClass, FalseClass ],
    "array"   => [ Array ],
    "object"  => [ Hash ],
    "null"    => [ NilClass ]
  }.freeze

  class << self
    def register(name, klass)
      registry[name.to_s] = klass
    end

    def lookup(name)
      registry[name.to_s]
    end

    def all_definitions
      registry.values.map(&:tool_definition)
    end

    def invoke(name:, input:, user:)
      klass = lookup(name) or return Tool::Result.failure("unknown tool: #{name}")
      sanitized = input.to_h.deep_stringify_keys
      error = validation_error(sanitized, klass.input_schema)
      return Tool::Result.failure("invalid input: #{error}") if error
      klass.invoke(input: sanitized, user: user)
    end

    # Minimal schema check at the registry boundary. Returns nil if `input`
    # satisfies `schema`, otherwise a short human-readable error string.
    # Phase 3 ships only what we need; a full JSON-schema validator can
    # land in Phase 4/5 if MCP tools start declaring richer schemas.
    def validation_error(input, schema)
      return nil unless schema.is_a?(Hash)
      properties = (schema[:properties] || schema["properties"] || {})
      required   = Array(schema[:required] || schema["required"])

      missing = required.find { |key| !input.key?(key.to_s) }
      return "missing required key #{missing.inspect}" if missing

      properties.each do |key, prop_schema|
        key_s = key.to_s
        next unless input.key?(key_s)
        expected = (prop_schema[:type] || prop_schema["type"]).to_s
        allowed  = TYPE_MAP[expected]
        next unless allowed
        value = input[key_s]
        next if allowed.any? { |k| value.is_a?(k) }
        return "key #{key_s.inspect} must be a #{expected}, got #{value.class}"
      end

      nil
    end

    private
      def registry
        @registry ||= {}
      end
  end

  # Subclasses implement these three.
  def self.tool_name;   raise NotImplementedError; end
  def self.description; raise NotImplementedError; end
  def self.input_schema; raise NotImplementedError; end

  def self.tool_definition
    { name: tool_name, description: description, input_schema: input_schema }
  end
end
