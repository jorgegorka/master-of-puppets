# Phase 4 § 15.7: application-wide CSP. The directives are chosen to support
# xterm.js (inline styles), the (future) Monaco editor via esm.sh, and the
# Action Cable WebSocket. Each directive is scoped tightly — bumping it
# requires a comment line explaining what new surface needs it.

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.style_src   :self, :unsafe_inline                  # xterm.js + monaco inline styles
  policy.script_src  :self, "https://esm.sh", "https://ga.jspm.io" # Monaco + chart.js CDNs
  policy.worker_src  :self, :blob                           # Monaco workers
  policy.connect_src :self, "wss:", "ws:"                   # Action Cable
  policy.img_src     :self, :data, :blob
  policy.media_src   :self, :data
  policy.font_src    :self, :data
  policy.object_src  :none
  policy.base_uri    :self
  policy.frame_ancestors :none
end

Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
Rails.application.config.content_security_policy_report_only = false
