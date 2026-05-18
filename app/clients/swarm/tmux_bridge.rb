module Swarm
  # Rails-side facade over the supervisor's swarm.* JSON-RPC methods.
  # Mirrors Terminal::TmuxManager: cwd is hardened through WorkspacePath
  # before reaching the supervisor, so a malicious raw path like
  # '../../etc' on an agent profile is caught here and never touches
  # `tmux new-session -c ...`. The supervisor still uses array-form Open3
  # and integer coercion as defence-in-depth.
  class TmuxBridge
    DEFAULT_COLS = 120
    DEFAULT_ROWS = 40

    def self.spawn_worker(assignment)
      profile = assignment.agent_profile
      cwd     = WorkspacePath.resolve(root: ".", raw: relative_cwd(profile.cwd)).to_s
      AgentsSupervisor::Client.call(
        "swarm.spawn_worker",
        {
          assignment_id: assignment.id,
          profile_slug:  profile.slug,
          cwd:           cwd,
          cols:          DEFAULT_COLS,
          rows:          DEFAULT_ROWS
        }
      )
    end

    def self.send_keys(assignment, data)
      AgentsSupervisor::Client.call("swarm.send_keys", { assignment_id: assignment.id, data: data })
    end

    def self.close_worker(assignment)
      AgentsSupervisor::Client.call("swarm.close_worker", { assignment_id: assignment.id })
    end

    def self.fifo_path(assignment)
      Rails.root.join("tmp/sockets/swarm-#{assignment.id}.fifo")
    end

    private_class_method def self.relative_cwd(raw_cwd)
      base = Pathname.new(Rails.application.config.x.mop_home).realpath
      candidate = Pathname.new(raw_cwd.to_s)
      if candidate.absolute?
        # Convert absolute paths to workspace-relative so WorkspacePath can
        # vet them; if the absolute path lives outside ${MOP_HOME}, the
        # relative_path_from yields "../..." which WorkspacePath rejects.
        candidate.cleanpath.relative_path_from(base).to_s
      else
        raw_cwd.to_s.presence || "."
      end
    end
  end
end
