class Message::AdvanceJob < ApplicationJob
  queue_as :default

  def perform(message)
    message.advance!
  end
end
