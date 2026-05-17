class AddSwarmAssignmentToChatSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :chat_sessions, :swarm_assignment, foreign_key: true
  end
end
