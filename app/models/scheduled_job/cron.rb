class ScheduledJob::Cron
  class Invalid     < StandardError; end
  class TooFrequent < StandardError; end

  MIN_INTERVAL_SECONDS = 60  # SchedulerTickJob fires every 60s; finer is meaningless.

  def initialize(expression)
    @expression = expression.to_s
    @cron       = Fugit::Cron.parse(@expression)
    raise Invalid, "#{@expression.inspect} is not a valid cron expression" unless @cron
    raise TooFrequent, "sub-minute cron #{@expression.inspect} rejected (SchedulerTickJob fires every 60s)" if too_frequent?
  end

  def next_run_at(from: Time.current)
    Time.at(@cron.next_time(from).to_i).utc
  end

  private
    def too_frequent?
      sample = @cron.next_time(Time.at(0)).to_i
      delta  = @cron.next_time(Time.at(sample)).to_i - sample
      delta < MIN_INTERVAL_SECONDS
    end
end
