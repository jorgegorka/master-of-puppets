module CurrentUserActiveJobExtensions
  extend ActiveSupport::Concern

  prepended do
    attr_reader :captured_user
    self.enqueue_after_transaction_commit = true
  end

  def initialize(...)
    super
    @captured_user = Current.user
  end

  def serialize
    super.merge("captured_user" => @captured_user&.to_global_id&.to_s)
  end

  def deserialize(job_data)
    super
    if (gid = job_data["captured_user"])
      @captured_user = GlobalID::Locator.locate(gid)
    end
  end

  def perform_now
    if @captured_user
      Current.set(user: @captured_user) { super }
    else
      super
    end
  end
end

ActiveSupport.on_load(:active_job) do
  ActiveJob::Base.prepend CurrentUserActiveJobExtensions
end
