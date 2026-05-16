Skill::SecurityAnalysis = Data.define(:declared_level, :heuristic_flags, :final_level) do
  LEVELS = %i[safe low medium high].freeze

  # Heuristics scan fenced code blocks only — prose backticks and bare URLs in
  # documentation no longer trip the upgrade. The reader-friendly summary of
  # what a skill does belongs in prose; what it *runs* belongs in code fences.
  FENCED_CODE_RE = /```.*?```/m

  SHELL_PATTERNS = [
    /\brun_shell\b/i,
    /\bsystem\s*\(/,
    /\$\([^)]+\)/,
    /\beval\b/i,
    /\bexec\b/i,
    /\bKernel\.(?:spawn|system|exec|fork)\b/,
    /\bIO\.popen\b/,
    /\bOpen3\./,
    /\bProcess\.(?:spawn|fork|exec)\b/
  ].freeze

  # Library-shape matches only. Bare https:// URLs in prose are not a signal.
  NETWORK_PATTERNS = [
    /\bnet\/http\b/i,
    /\bfaraday\b/i,
    /\bExcon\b/,
    /\bURI\.open\b/,
    /\bNet::HTTP\b/,
    /\bHTTParty\b/
  ].freeze

  FILE_WRITE_PATTERNS = [
    /\bwrite_file\b/i,
    /\bFile\.write\b/i,
    /\bFileUtils\.(?:mv|cp|rm)\b/i
  ].freeze

  def self.from(declared:, body:)
    scanned = body.to_s.scan(FENCED_CODE_RE).join("\n")
    flags = []
    flags << :shell      if SHELL_PATTERNS.any?      { |re| scanned =~ re }
    flags << :network    if NETWORK_PATTERNS.any?    { |re| scanned =~ re }
    flags << :file_write if FILE_WRITE_PATTERNS.any? { |re| scanned =~ re }

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
