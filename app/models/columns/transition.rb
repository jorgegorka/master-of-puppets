module Columns
  class Transition
    include ActiveModel::Model
    include ActiveModel::Attributes

    KINDS = %w[advance reject block manual_move cancel].freeze

    attr_accessor :task, :actor, :kind, :reason, :feedback, :target_column, :target_column_name

    validates :task, presence: true
    validates :actor, presence: true
    validates :kind, presence: true, inclusion: { in: KINDS }

    validate :validate_actor_compatibility
    validate :resolve_target_column

    def initialize(task:, actor:, kind:, reason: nil, feedback: nil, target_column: nil, target_column_name: nil)
      @task = task
      @actor = actor
      @kind = kind.to_s
      @reason = reason
      @feedback = feedback
      @target_column = target_column
      @target_column_name = target_column_name
    end

    def source_column
      task&.column
    end

    def actor_for_audit
      case actor
      when User then actor
      when Run  then actor.column
      when Column then actor
      else actor
      end
    end

    def call
      return false unless valid?
      true
    end

    private

    def validate_actor_compatibility
      return unless task && source_column

      case kind
      when "advance", "reject", "block"
        unless actor_runs_on_column?
          errors.add(:actor, "agent transitions require a Run actor on the source agent column")
        end
        unless source_column.agent?
          errors.add(:kind, "#{kind} only allowed from agent-policy columns")
        end
      when "manual_move", "cancel"
        unless actor.is_a?(User)
          errors.add(:actor, "manual transitions require a User actor")
        end
        if kind == "manual_move" && !source_column.manual?
          errors.add(:kind, "manual_move only allowed from manual-policy columns")
        end
      end
    end

    def actor_runs_on_column?
      case actor
      when Run
        actor.column_id == source_column.id
      when Column
        actor.id == source_column.id
      else
        false
      end
    end

    def resolve_target_column
      return unless task && source_column

      resolved = case kind
      when "advance" then resolve_advance_target
      when "reject"  then resolve_reject_target
      when "block"   then resolve_block_target
      when "cancel"  then resolve_cancel_target
      when "manual_move" then resolve_manual_target
      end

      if resolved.nil?
        errors.add(:target_column, "could not be resolved for kind=#{kind}")
        return
      end

      unless resolved.project_id == source_column.project_id
        errors.add(:target_column, "must belong to the same project")
        return
      end

      @target_column = resolved
    end

    def resolve_advance_target
      return target_column if target_column
      return find_by_name(target_column_name) if target_column_name.present?

      project.columns
             .ordered
             .where("position > ?", source_column.position)
             .first
    end

    def resolve_reject_target
      return target_column if target_column
      return find_by_name(target_column_name) if target_column_name.present?

      project.columns
             .ordered
             .non_terminal
             .where("position < ?", source_column.position)
             .last
    end

    def resolve_block_target
      project.columns.find_by(system_key: "blocked")
    end

    def resolve_cancel_target
      project.columns.find_by(system_key: "cancelled")
    end

    def resolve_manual_target
      target_column || find_by_name(target_column_name)
    end

    def find_by_name(name)
      project.columns.where("LOWER(name) = ?", name.to_s.downcase).first
    end

    def project
      source_column&.project
    end
  end
end
