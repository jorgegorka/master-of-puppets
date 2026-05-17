# Per-user dashboard cable. Production browsers subscribe via
# Turbo Streams from the dashboard view, which uses Turbo::StreamsChannel
# under the hood — the same stream key the broadcasts in JobRun, Message,
# and McpServer target. This channel exists for explicit Action Cable
# consumers (custom JS clients, ops tooling) that want the raw frames
# without the Turbo wrapper.
class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard:#{current_user.id}"
  end
end
