class AddExpiresAtToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :expires_at, :datetime
    Session.reset_column_information
    # SQLite stores DATETIME as ISO 8601 TEXT; the `+ N` SQL idiom would parse
    # the leading digits as a number and silently produce garbage values. Doing
    # the arithmetic in Ruby is adapter-agnostic and produces real timestamps.
    Session.find_each do |s|
      s.update_columns(expires_at: (s.last_seen_at || s.created_at) + Session::Sweepable::DEFAULT_TTL)
    end
    change_column_null :sessions, :expires_at, false
    add_index :sessions, :expires_at
  end
end
