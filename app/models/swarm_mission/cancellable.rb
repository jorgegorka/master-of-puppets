module SwarmMission::Cancellable
  extend ActiveSupport::Concern

  included do
    has_one :cancel_record, class_name: "SwarmMission::Cancellation",
                            foreign_key: :swarm_mission_id,
                            dependent: :destroy
  end

  def cancelled_by_record?
    cancel_record.present?
  end

  def cancel(reason: nil, user: Current.user)
    return if cancelled?

    transaction do
      create_cancel_record!(user: user, reason: reason)
      update!(state: :cancelled)
      assignments.live.find_each { |a| a.update!(state: :cancelled) }
      track_event :cancelled, creator: user, reason: reason
    end
  end
end
