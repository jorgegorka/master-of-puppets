class DirectorServer
  PROTOCOL_VERSION = "2024-11-05"

  TOOL_SCOPES = {
    agent: [
      Tools::AdvanceTask,
      Tools::RejectTask,
      Tools::BlockTask,
      Tools::CreateTask,
      Tools::AddMessage,
      Tools::ListMyTasks,
      Tools::GetTaskDetails,
      Tools::ListColumns,
      Tools::FindColumn,
      Tools::SearchDocuments,
      Tools::GetDocument
    ]
  }.freeze

  attr_reader :column, :tool_scope

  def initialize(column, tool_scope: :agent)
    @column = column
    @tool_scope = tool_scope.to_sym
    @tools = DirectorServer.tool_classes_for(@tool_scope).map { |klass| klass.new(column) }
  end

  def run
    $stdin.each_line do |line|
      request = JSON.parse(line.strip)
      response = handle(request)
      $stdout.puts(response.to_json) if response
      $stdout.flush
    rescue JSON::ParserError
      $stdout.puts(error_response(nil, -32700, "Parse error").to_json)
      $stdout.flush
    end
  end

  def self.tool_classes_for(scope)
    TOOL_SCOPES.fetch(scope.to_sym) do
      raise ArgumentError, "Unknown DirectorServer tool scope: #{scope.inspect}"
    end
  end

  def self.tool_classes
    tool_classes_for(:agent)
  end

  private

  def handle(request)
    id = request["id"]
    method = request["method"]

    case method
    when "initialize"
      handle_initialize(id)
    when "notifications/initialized"
      nil
    when "tools/list"
      handle_tools_list(id)
    when "tools/call"
      handle_tools_call(id, request["params"])
    else
      error_response(id, -32601, "Method not found: #{method}")
    end
  end

  def handle_initialize(id)
    {
      jsonrpc: "2.0",
      id: id,
      result: {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "director", version: "1.0.0" }
      }
    }
  end

  def handle_tools_list(id)
    {
      jsonrpc: "2.0",
      id: id,
      result: {
        tools: @tools.map(&:definition)
      }
    }
  end

  def handle_tools_call(id, params)
    tool_name = params&.dig("name")
    arguments = params&.dig("arguments") || {}

    tool = @tools.find { |t| t.name == tool_name }
    return error_response(id, -32602, "Unknown tool: #{tool_name}") unless tool

    arguments = sanitize_arguments!(tool, arguments)
    result = tool.call(arguments)

    {
      jsonrpc: "2.0",
      id: id,
      result: {
        content: [ { type: "text", text: result.to_json } ]
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    tool_error_response(id, e.message)
  rescue ActiveRecord::RecordNotFound => e
    tool_error_response(id, e.message)
  rescue ArgumentError => e
    tool_error_response(id, e.message)
  end

  def error_response(id, code, message)
    { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
  end

  def tool_error_response(id, message)
    {
      jsonrpc: "2.0",
      id: id,
      result: {
        content: [ { type: "text", text: message } ],
        isError: true
      }
    }
  end

  def sanitize_arguments!(tool, arguments)
    schema = tool.definition[:inputSchema] || {}
    properties = (schema[:properties] || {}).keys.map(&:to_s)
    required = (schema[:required] || []).map(&:to_s)

    sanitized = arguments.slice(*properties)

    missing = required - sanitized.keys
    if missing.any?
      raise ArgumentError,
        "Missing required argument(s) for #{tool.name}: #{missing.join(', ')}. Valid arguments: #{properties.join(', ')}."
    end

    sanitized
  end
end
