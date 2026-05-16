module Skill::SecurityAnalyzable
  extend ActiveSupport::Concern

  def security_analysis
    Skill::SecurityAnalysis.from(
      declared: manifest["security_level"] || "safe",
      body:     body
    )
  end
end
