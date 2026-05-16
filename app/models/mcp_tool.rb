class McpTool < ApplicationRecord
  belongs_to :mcp_server

  scope :exposed, -> { joins(:mcp_server).merge(McpServer.reachable) }

  def invoke(input:, user:)
    raise "tenant violation" unless mcp_server.user_id == user.id

    begin
      client = Mcp::HttpClient.new(mcp_server)
      output = client.call_tool(name, input)
      Tool::Result.ok(output.to_s)
    rescue => e
      Tool::Result.failure("mcp tool '#{name}' failed: #{e.message.to_s[0, 255]}")
    end
  end

  def self.lookup(name)
    exposed.find_by(name: name)
  end
end
