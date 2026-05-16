class Terminal::SweepJob < ApplicationJob
  queue_as :default

  def perform
    TerminalSession.sweep!
  end
end
