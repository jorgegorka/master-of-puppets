module Message::Streamable
  extend ActiveSupport::Concern

  def advance!
    raise NotImplementedError, "implemented in Task 1.9"
  end

  def advance_later
    Message::AdvanceJob.perform_later(self)
  end
end
