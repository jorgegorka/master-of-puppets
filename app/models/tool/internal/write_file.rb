class Tool::Internal::WriteFile < Tool::Internal
  MAX_BYTES = 1 * 1024 * 1024 # 1 MiB

  def self.tool_name;   "write_file"; end
  def self.description; "Write content to a file in the workspace (atomic: tmp → fsync → rename)."; end
  def self.input_schema
    {
      type: "object",
      properties: {
        path:    { type: "string" },
        content: { type: "string" }
      },
      required: %w[path content]
    }
  end

  def self.invoke(input:, user:)
    content = input.fetch("content")
    return Tool::Result.failure("content too large") if content.bytesize > MAX_BYTES

    wsp = WorkspacePath.resolve(root: ".", raw: input.fetch("path"))
    FileUtils.mkdir_p(wsp.absolute.dirname)
    tmp = wsp.absolute.dirname.join(".#{wsp.absolute.basename}.#{SecureRandom.hex(4)}.tmp")
    File.open(tmp, "w") do |f|
      f.write(content)
      f.fsync
    end
    File.rename(tmp, wsp.absolute)
    Tool::Result.ok("wrote #{content.bytesize} bytes to #{wsp.rel}")
  rescue WorkspacePath::EscapeAttempt => e
    Tool::Result.failure("forbidden: #{e.message}")
  ensure
    File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
  end
end
