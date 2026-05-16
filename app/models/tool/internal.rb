class Tool::Internal
  class UnknownTool < StandardError; end
  class Forbidden  < StandardError; end

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
      klass = lookup(name) or raise UnknownTool, name
      klass.invoke(input: input.to_h.deep_stringify_keys, user: user)
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
