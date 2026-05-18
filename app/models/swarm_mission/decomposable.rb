module SwarmMission::Decomposable
  extend ActiveSupport::Concern

  JSON_FENCE_RE = /```(?:json)?\s*\n(.*?)\n```/m

  def decompose!
    return unless planning?

    @created_assignment_ids = []
    raw  = run_conductor_turn
    plan = parse_plan(raw)
    validate_plan!(plan)

    transaction do
      plan["assignments"].each do |entry|
        profile = AgentProfile.find_by!(slug: entry.fetch("agent_slug"))
        deps    = Array(entry["depends_on"]).map { |i| @created_assignment_ids[i - 1] or raise "invalid depends_on index #{i}" }
        asg = assignments.create!(
          agent_profile:   profile,
          task:            entry.fetch("task"),
          rationale:       entry["rationale"],
          depends_on:      deps,
          review_required: entry.fetch("review_required", false)
        )
        @created_assignment_ids << asg.id
      end
      update!(state: :dispatching, decomposition_notes: plan["decomposition_notes"])
      track_event :decomposed, count: plan["assignments"].size
    end
    SwarmEvent.log!(mission: self, kind: "decomposed", message: "Mission decomposed",
                    data: { count: plan["assignments"].size })
  rescue => e
    Rails.logger.warn("[SwarmMission#decompose!] #{e.class}: #{e.message}")
    update!(state: :planning_failed)
    track_event :decomposition_failed, error: e.message.to_s.first(255)
    SwarmEvent.log!(mission: self, kind: "decomposition_failed", message: e.message, data: {})
  end

  def decompose_later
    Swarm::DecompositionJob.perform_later(self)
  end

  private
    def run_conductor_turn
      chat = ChatSession.create!(
        user:           user,
        title:          "Conductor decomposition: #{title}",
        model:          AgentProfile.first&.model    || "claude-sonnet-4-5",
        provider:       AgentProfile.first&.provider || "anthropic",
        last_active_at: Time.current
      )
      prompt = Conductor::Prompts.decomposition(
        mission:  self,
        profiles: AgentProfile.rostered.to_a,
        user:     user
      )
      chat.messages.create!(
        role:           :user,
        status:         :completed,
        content_blocks: [ { type: "text", text: prompt } ],
        model:          chat.model,
        provider:       chat.provider
      )
      assistant = chat.messages.create!(
        role:           :assistant,
        status:         :pending,
        content_blocks: [],
        model:          chat.model,
        provider:       chat.provider
      )
      assistant.advance!
      Array(assistant.reload.content_blocks).filter_map { |b|
        b["text"] if b.is_a?(Hash) && b["type"] == "text"
      }.join("\n\n")
    end

    def parse_plan(raw)
      fenced = raw.to_s[JSON_FENCE_RE, 1] || raw.to_s
      JSON.parse(fenced)
    end

    def validate_plan!(plan)
      raise "missing 'assignments' key" unless plan.is_a?(Hash) && plan["assignments"].is_a?(Array)

      plan["assignments"].each_with_index do |entry, idx|
        raise "assignment #{idx + 1}: missing agent_slug" if entry["agent_slug"].blank?
        raise "assignment #{idx + 1}: missing task"        if entry["task"].blank?
        slug = entry["agent_slug"]
        unless AgentProfile.exists?(slug: slug, enabled: true)
          raise "unknown agent_slug '#{slug}'"
        end
        Array(entry["depends_on"]).each do |dep|
          unless dep.is_a?(Integer) && dep.between?(1, idx)
            raise "assignment #{idx + 1}: invalid depends_on #{dep.inspect} (must reference an earlier assignment)"
          end
        end
      end
    end
end
