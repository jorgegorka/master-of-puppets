class Session::SweepJob < ApplicationJob
  queue_as :default

  def perform
    Session.sweep!
  end
end
