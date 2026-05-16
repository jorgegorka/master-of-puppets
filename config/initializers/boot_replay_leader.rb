module BootReplayLeader
  # Single-worker Puma never sets PUMA_WORKER_INDEX (on_worker_boot only fires
  # in cluster mode), so it defaults to "0" → leader. Cluster Puma only enters
  # this branch from worker 0.
  def self.leader?
    ENV.fetch("PUMA_WORKER_INDEX", "0").to_i.zero?
  end
end
