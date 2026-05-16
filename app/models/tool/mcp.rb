module Tool::Mcp
  # All MCP tool definitions exposed to a given user — joins through
  # mcp_servers so a disabled / errored server's tools never reach the LLM.
  def self.all_definitions(user:)
    return [] if user.nil?

    McpTool.exposed.where(mcp_server: { user_id: user.id }).map do |t|
      {
        name:         t.name,
        description:  t.description.to_s,
        input_schema: schema_for(t)
      }
    end
  end

  def self.lookup(name)
    McpTool.lookup(name)
  end

  def self.invoke(name:, input:, user:)
    tool = lookup(name)
    return Tool::Result.failure("unknown mcp tool: #{name}") unless tool
    return Tool::Result.failure("mcp tool '#{name}' belongs to another user") unless tool.mcp_server.user_id == user&.id

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
