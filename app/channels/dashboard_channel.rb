class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard:#{current_user.id}"
  end
end
