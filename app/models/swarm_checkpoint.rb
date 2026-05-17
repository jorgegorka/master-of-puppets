class SwarmCheckpoint < ApplicationRecord
  belongs_to :swarm_assignment

  MARKER_RE = /===HERMES CHECKPOINT===\n(.*?)\n===END CHECKPOINT===/m

  # Returns Array<Hash> with symbolised top-level keys. Malformed YAML stanzas
  # are skipped (logged at Rails.logger.warn) — never raise into the
  # orchestrator loop, which would halt the mission.
  def self.parse(raw)
    raw.to_s.scan(MARKER_RE).filter_map do |(body)|
      begin
        yaml = YAML.safe_load(body, permitted_classes: [], aliases: false)
        next unless yaml.is_a?(Hash) && yaml["state_label"].is_a?(String)

        {
          state_label:   yaml["state_label"],
          runtime_state: yaml["runtime_state"] || {},
          files_changed: Array(yaml["files_changed"]),
          commands_run:  Array(yaml["commands_run"]),
          result:        yaml["result"],
          blocker:       yaml["blocker"],
          next_action:   yaml["next_action"],
          raw:           "===HERMES CHECKPOINT===\n#{body}\n===END CHECKPOINT==="
        }
      rescue Psych::Exception => e
        Rails.logger.warn("[SwarmCheckpoint] skipped malformed stanza: #{e.message}")
        nil
      end
    end
  end
end
