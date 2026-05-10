module Tasks
  module Recurrence
    extend ActiveSupport::Concern

    SPAWNED_ACTION = "goal_recurrence_spawned".freeze
    SKIPPED_ACTION = "goal_recurrence_skipped".freeze

    included do
      enum :recurrence_unit, { day: 0, week: 1, month: 2 }

      validates :recurrence_interval, numericality: { only_integer: true, in: 1..365 }, allow_nil: true
      validate :recurrence_fields_consistent
      validate :recurrence_only_on_root_tasks
    end

    class_methods do
      def scan_due_recurrences(now: Time.current)
        where("next_recurrence_at <= ?", now)
          .where(parent_task_id: nil)
          .where.not(recurrence_interval: nil)
          .find_each do |task|
          task.update_column(:next_recurrence_at, task.next_due_after(now))
          RecurrentGoalFireJob.perform_later(task.id)
        end
      end
    end

    def recurring?
      recurrence_interval.present?
    end

    def recurring_template?
      recurring? && root?
    end

    def make_recurrent(interval:, unit:, anchor_date:, anchor_hour:, timezone:)
      zone = ActiveSupport::TimeZone[timezone] or raise ArgumentError, "Unknown timezone: #{timezone}"
      date = anchor_date.is_a?(String) ? Date.parse(anchor_date) : anchor_date
      anchor_at = zone.local(date.year, date.month, date.day, Integer(anchor_hour), 0).utc
      int = Integer(interval)

      assign_attributes(
        recurrence_interval: int,
        recurrence_unit: unit.to_s,
        recurrence_anchor_at: anchor_at,
        recurrence_timezone: timezone,
        next_recurrence_at: compute_next_due_after(Time.current, anchor_at, int, unit.to_s, timezone)
      )
      save!
    end

    def stop_recurring
      assign_attributes(
        recurrence_interval: nil,
        recurrence_unit: nil,
        recurrence_anchor_at: nil,
        recurrence_last_fired_at: nil,
        recurrence_timezone: nil,
        next_recurrence_at: nil
      )
      save!
    end

    def fire_recurrence_now
      return unless recurring_template?
      return unless due_for_recurrence?

      transaction do
        predecessor = latest_recurrence_occurrence
        if predecessor && !predecessor.terminal?
          record_audit_event!(actor: audit_actor, action: SKIPPED_ACTION, metadata: {
            fired_at: Time.current,
            reason: "predecessor_open",
            predecessor_task_id: predecessor.id
          })
          update!(next_recurrence_at: next_due_after(Time.current))
        else
          clone = clone_for_recurrence
          clone.save!
          record_audit_event!(actor: audit_actor, action: SPAWNED_ACTION, metadata: {
            fired_at: Time.current,
            occurrence_task_id: clone.id
          })
          update!(
            recurrence_last_fired_at: Time.current,
            next_recurrence_at: next_due_after(Time.current)
          )
        end
      end
    end

    def fire_recurrence_later
      RecurrentGoalFireJob.perform_later(id)
    end

    def next_due_after(time)
      return nil unless recurring_template?
      compute_next_due_after(time, recurrence_anchor_at, recurrence_interval, recurrence_unit, recurrence_timezone)
    end

    def due_for_recurrence?(now: Time.current)
      return false unless recurring_template?
      return true if recurrence_interval == 1

      anchor = recurrence_anchor_at
      case recurrence_unit
      when "day"
        ((now.to_date - anchor.to_date).to_i % recurrence_interval).zero?
      when "week"
        anchor_local = anchor.in_time_zone(recurrence_timezone).to_date
        now_local = now.in_time_zone(recurrence_timezone).to_date
        ((now_local - anchor_local).to_i / 7 % recurrence_interval).zero?
      when "month"
        anchor_local = anchor.in_time_zone(recurrence_timezone)
        now_local = now.in_time_zone(recurrence_timezone)
        months_since = (now_local.year - anchor_local.year) * 12 + (now_local.month - anchor_local.month)
        (months_since % recurrence_interval).zero?
      end
    end

    private

    def recurrence_fields_consistent
      anchored = recurrence_interval.present? || recurrence_unit.present? || recurrence_anchor_at.present?
      return unless anchored

      errors.add(:recurrence_interval, "is required") if recurrence_interval.blank?
      errors.add(:recurrence_unit, "is required") if recurrence_unit.blank?
      errors.add(:recurrence_anchor_at, "is required") if recurrence_anchor_at.blank?
      errors.add(:recurrence_timezone, "is required") if recurrence_timezone.blank?
    end

    def recurrence_only_on_root_tasks
      if recurrence_interval.present? && parent_task_id.present?
        errors.add(:base, "Only root tasks can be recurrent")
      end
    end

    # Skip cycles in bulk (O(1) approximation), then fine-tune with at most
    # a couple of iterations to absorb calendar-math wobble (DST, month lengths).
    def compute_next_due_after(time, anchor, interval, unit, timezone)
      return nil unless interval&.positive? && anchor

      candidate =
        case unit
        when "day"
          cycles = [ ((time - anchor) / (interval * 1.day)).floor, 0 ].max
          anchor + (cycles * interval).days
        when "week"
          cycles = [ ((time - anchor) / (interval * 1.week)).floor, 0 ].max
          anchor + (cycles * interval).weeks
        when "month"
          a = anchor.in_time_zone(timezone)
          t = time.in_time_zone(timezone)
          months_diff = (t.year - a.year) * 12 + (t.month - a.month)
          cycles = [ months_diff / interval, 0 ].max
          anchor + (cycles * interval).months
        end

      candidate += interval.public_send(unit.pluralize) while candidate <= time
      candidate
    end

    def latest_recurrence_occurrence
      latest = audit_events.for_action(SPAWNED_ACTION).reverse_chronological.first
      occurrence_id = latest&.metadata&.dig("occurrence_task_id")
      occurrence_id ? Task.find_by(id: occurrence_id) : self
    end

    def clone_for_recurrence
      project.tasks.new(
        title: title,
        description: description,
        priority: priority,
        creator: creator,
        completion_percentage: 0
      )
    end
  end
end
