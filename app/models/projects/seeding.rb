module Projects
  module Seeding
    extend ActiveSupport::Concern

    included do
      after_create :seed_default_skills!
      after_create :seed_default_columns!
    end

    DEFAULT_COLUMNS = [
      {
        name: "Backlog",
        position: 1,
        transition_policy: "manual",
        terminal: false,
        kind: nil,
        system_key: "backlog",
        hidden_by_default: false,
        description: "Tasks waiting to be picked up."
      },
      {
        name: "In Progress",
        position: 2,
        transition_policy: "agent",
        terminal: false,
        kind: nil,
        system_key: "in_progress",
        hidden_by_default: false,
        description: "Active work in progress. Configure adapter, job_spec, and success_criteria to enable the agent."
      },
      {
        name: "Review",
        position: 3,
        transition_policy: "manual",
        terminal: false,
        kind: "review",
        system_key: "review",
        hidden_by_default: false,
        description: "Tasks awaiting human review."
      },
      {
        name: "Done",
        position: 4,
        transition_policy: "manual",
        terminal: true,
        kind: "done",
        system_key: "done",
        hidden_by_default: false,
        description: "Completed tasks."
      },
      {
        name: "Blocked",
        position: 5,
        transition_policy: "manual",
        terminal: false,
        kind: "blocked",
        system_key: "blocked",
        hidden_by_default: true,
        description: "Tasks flagged as blocked."
      },
      {
        name: "Cancelled",
        position: 6,
        transition_policy: "manual",
        terminal: true,
        kind: "cancelled",
        system_key: "cancelled",
        hidden_by_default: true,
        description: "Cancelled tasks."
      }
    ].freeze

    def seed_default_skills!
      self.class.default_skill_definitions.each do |data|
        skills.find_or_create_by!(key: data.fetch("key")) do |skill|
          skill.name = data.fetch("name")
          skill.description = data["description"]
          skill.markdown = data.fetch("markdown")
          skill.category = data["category"]
          skill.builtin = true
        end
      end
    end

    def seed_default_columns!
      DEFAULT_COLUMNS.each do |attrs|
        next if columns.exists?(system_key: attrs[:system_key])
        columns.create!(attrs.dup.tap do |a|
          a[:adapter_config] ||= {}
        end)
      end
    end

    class_methods do
      def default_skill_definitions
        @default_skill_definitions ||= Dir[Rails.root.join("db/seeds/skills/*.yml")].map { |file| YAML.load_file(file) }.freeze
      end
    end
  end
end
