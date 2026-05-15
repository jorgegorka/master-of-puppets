class Current < ActiveSupport::CurrentAttributes
  attribute :user, :session, :ip_address, :user_agent
end
