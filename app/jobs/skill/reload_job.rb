class Skill::ReloadJob < ApplicationJob
  queue_as :default

  # Boot-replay + per-worker supervisor fan-out enqueue this job N× per Puma
  # worker for the same path. Discard duplicates rather than re-parse the
  # same SKILL.md N times. (Worker-0 gating — a true single-leader replay —
  # lands with Phase 4 supervisor v2.)
  limits_concurrency to: 1, key: ->(path: nil) { "skill-reload:#{path || 'all'}" }, on_conflict: :discard

  # When path is nil, walks the whole tree (boot-time replay).
  # When path is set, loads just that one file (supervisor watcher callback).
  def perform(path: nil)
    path ? Skill.reload_path(path) : Skill.reload_from_disk
  end
end
