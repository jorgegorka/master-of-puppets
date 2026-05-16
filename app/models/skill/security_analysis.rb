Skill::SecurityAnalysis = Data.define(:declared_level, :heuristic_flags, :final_level) do
  LEVELS = %i[safe low medium high].freeze

  SHELL_PATTERNS    = [ /run_shell/i, /system\s*\(/, /`[^`]+`/, /\$\([^)]+\)/ ].freeze
  NETWORK_PATTERNS  = [ /https?:\/\//i, /net\/http/i, /faraday/i, /Excon/i ].freeze
  FILE_WRITE_PATTERNS = [ /write_file/i, /File\.write/i, /FileUtils\.(?:mv|cp|rm)/i ].freeze

  def self.from(declared:, body:)
    flags = []
    flags << :shell    if SHELL_PATTERNS.any?     { |re| body =~ re }
    flags << :network  if NETWORK_PATTERNS.any?   { |re| body =~ re }
    flags << :file_write if FILE_WRITE_PATTERNS.any? { |re| body =~ re }

    heuristic_min = if flags.include?(:network)    then :high
                    elsif flags.include?(:shell)   then :medium
                    elsif flags.include?(:file_write) then :low
                    else :safe
                    end

    declared_sym = declared.to_sym
    final = [ declared_sym, heuristic_min ].max_by { |l| LEVELS.index(l) }
    new(declared_sym, flags, final)
  end
end
