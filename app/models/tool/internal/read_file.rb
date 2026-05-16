class Tool::Internal::ReadFile < Tool::Internal
  MAX_BYTES = 256 * 1024

  def self.tool_name;   "read_file"; end
  def self.description; "Read a UTF-8 text file from the workspace."; end
  def self.input_schema
    {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to ${MOP_HOME}, e.g. memory/notes/a.md" }
      },
      required: [ "path" ]
    }
  end

  def self.invoke(input:, user:)
    wsp = WorkspacePath.resolve(root: ".", raw: input.fetch("path"))
    return Tool::Result.failure("not found: #{input["path"]}") unless wsp.exist?
    return Tool::Result.failure("path is a directory") if wsp.absolute.directory?

    bytes = File.size(wsp.absolute)
    if bytes > MAX_BYTES
      return Tool::Result.failure("file is #{bytes} bytes (max #{MAX_BYTES})")
    end

    Tool::Result.ok(wsp.read)
  rescue WorkspacePath::EscapeAttempt => e
    Tool::Result.failure("forbidden: #{e.message}")
  end
end
