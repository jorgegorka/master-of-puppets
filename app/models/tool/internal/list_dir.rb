class Tool::Internal::ListDir < Tool::Internal
  def self.tool_name;   "list_dir"; end
  def self.description; "List the contents of a workspace directory (one level)."; end
  def self.input_schema
    {
      type: "object",
      properties: {
        path: { type: "string", description: "Directory path relative to ${MOP_HOME}. Empty string for root." }
      },
      required: [ "path" ]
    }
  end

  def self.invoke(input:, user:)
    raw = input.fetch("path", "").to_s
    raw = "." if raw.empty?
    wsp = WorkspacePath.resolve(root: ".", raw: raw)
    return Tool::Result.failure("not a directory: #{raw}") unless wsp.absolute.directory?

    entries = wsp.absolute.children.map do |c|
      kind = c.directory? ? "dir" : "file"
      size = c.directory? ? "-" : c.size.to_s
      "#{kind}\t#{size}\t#{c.basename}"
    end.sort
    Tool::Result.ok(entries.join("\n"))
  rescue WorkspacePath::EscapeAttempt => e
    Tool::Result.failure("forbidden: #{e.message}")
  end
end
