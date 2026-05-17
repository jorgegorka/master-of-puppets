module Tool::Mcp
  # All MCP tool definitions exposed to a given user — joins through
  # mcp_servers so a disabled / errored server's tools never reach the LLM.
  def self.all_definitions(user:)
    return [] if user.nil?

    McpTool.exposed.where(mcp_server: { user_id: user.id }).map do |t|
      {
        name: t.name,
        description: t.description.to_s,
        input_schema: schema_for(t)
      }
    end
  end

  # Symmetric with Tool::Internal.allowed_for(user). MCP tools are already
  # tenant-scoped via mcp_servers.user_id, so this is a thin alias — but
  # keeping the same method name lets Message::Streamable compose both
  # registries uniformly without special-casing kwargs.
  def self.allowed_for(user)
    all_definitions(user: user)
  end

  def self.lookup(name, user:)
    McpTool.lookup(name, user: user)
  end

  def self.invoke(name:, input:, user:)
    tool = lookup(name, user: user)
    return Tool::Result.failure("unknown mcp tool: #{name}") unless tool

    tool.invoke(input: input, user: user)
  end

  # input_schema is stored as JSON; SQLite returns it as a String, postgres as
  # a Hash. Coerce so callers downstream always get a Hash.
  def self.schema_for(tool)
    raw = tool.input_schema
    return raw if raw.is_a?(Hash)

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end
end
