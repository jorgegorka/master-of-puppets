class AddExpiresAtToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :expires_at, :datetime
    Session.reset_column_information
    Session.in_batches.update_all("expires_at = COALESCE(last_seen_at, created_at) + #{30 * 24 * 3600}")
    change_column_null :sessions, :expires_at, false
    add_index :sessions, :expires_at
  end
end
