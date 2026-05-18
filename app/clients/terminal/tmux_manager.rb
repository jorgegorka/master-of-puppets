module Terminal
  # Rails-side facade over the supervisor's terminal.* JSON-RPC methods.
  # cwd is hardened through WorkspacePath.resolve before reaching the
  # supervisor, so a malicious raw path like '../../etc' is caught here
  # and never touches `tmux new-session -c ...`. The supervisor still
  # uses array-form Open3 as defence-in-depth.
  class TmuxManager
    def self.create(terminal_session)
      cwd = WorkspacePath.resolve(root: ".", raw: relative_cwd(terminal_session.cwd)).to_s
      AgentsSupervisor::Client.call(
        "terminal.create",
        {
          session_id: terminal_session.id,
          cwd:        cwd,
          cols:       terminal_session.cols,
          rows:       terminal_session.rows
        }
      )
    end

    def self.send_keys(terminal_session, data)
      AgentsSupervisor::Client.call("terminal.input", { session_id: terminal_session.id, data: data })
    end

    def self.resize(terminal_session, cols, rows)
      AgentsSupervisor::Client.call("terminal.resize", { session_id: terminal_session.id, cols: cols, rows: rows })
    end

    def self.close(terminal_session)
      AgentsSupervisor::Client.call("terminal.close", { session_id: terminal_session.id })
    end

    def self.capture(terminal_session, lines: 500)
      AgentsSupervisor::Client.call("terminal.capture", { session_id: terminal_session.id, lines: lines })
    end

    def self.fifo_path(terminal_session)
      Rails.root.join("tmp/sockets/term-#{terminal_session.id}.fifo")
    end

    private_class_method def self.relative_cwd(raw_cwd)
      base = Pathname.new(Rails.application.config.x.mop_home).realpath
      candidate = Pathname.new(raw_cwd.to_s)
      if candidate.absolute?
        # Convert absolute paths to workspace-relative so WorkspacePath can
        # vet them; if the absolute path lives outside ${MOP_HOME}, the
        # relative_path_from will yield "../..." which WorkspacePath rejects.
        cleaned = candidate.cleanpath
        cleaned.relative_path_from(base).to_s
      else
        raw_cwd.to_s.presence || "."
      end
    end
  end
end
