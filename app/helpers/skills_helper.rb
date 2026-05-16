module SkillsHelper
  SECURITY_BADGE_CLASS = {
    "safe"   => "badge badge--ok",
    "low"    => "badge badge--ok",
    "medium" => "badge badge--warn",
    "high"   => "badge badge--danger"
  }.freeze

  def security_badge(skill)
    content_tag :span, skill.security_level, class: SECURITY_BADGE_CLASS.fetch(skill.security_level, "badge")
  end
end
