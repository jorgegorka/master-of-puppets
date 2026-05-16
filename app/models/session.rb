class Session < ApplicationRecord
  include Eventable
  include Sweepable

  belongs_to :user

  before_create { self.last_seen_at ||= Time.current }
end
