class McpTool < ApplicationRecord
  belongs_to :mcp_server

  # `joins(:mcp_server)` aliases the join table as 'mcp_server' (singular,
  # matching the belongs_to name), so a chained .merge(McpServer.reachable)
  # would emit WHERE "mcp_servers".status — the unaliased table name — and
  # blow up. Inline the status filter with the alias instead.
  scope :exposed, -> { joins(:mcp_server).where(mcp_server: { status: McpServer.statuses[:reachable] }) }

  def invoke(input:, user:)
    raise "tenant violation" unless mcp_server.user_id == user.id

    begin
      client = Mcp::HttpClient.new(mcp_server)
      output = client.call_tool(name, input)
      Tool::Result.ok(output.to_s)
    rescue StandardError => e
      Tool::Result.failure("mcp tool '#{name}' failed: #{e.message.to_s[0, 255]}")
    end
  end

  # Scoped by user: two tenants may both expose a tool named "search". Without
  # the scope, user B's LLM call lands on user A's row, fails the tenant check,
  # and the LLM gets "belongs to another user" — which both misroutes the call
  # and discloses that another tenant owns a tool of that name.
  def self.lookup(name, user:)
    return nil if user.nil?

    exposed.where(mcp_server: { user_id: user.id }).find_by(name: name)
  end
end
