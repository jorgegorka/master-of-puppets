Tool::Result = Data.define(:output, :error, :is_error) do
  def self.ok(output)     = new(output, nil, false)
  def self.failure(error) = new(nil,    error, true)

  def to_tool_block(provider_tool_id)
    {
      "type"        => "tool_result",
      "tool_use_id" => provider_tool_id,
      "content"     => is_error ? error.to_s : output.to_s,
      "is_error"    => is_error
    }
  end
end
