module Columns
  module Budgeting
    extend ActiveSupport::Concern

    def budget_configured?
      agent? && budget_cents.to_i > 0
    end

    def budget_dollars
      budget_cents ? budget_cents / 100.0 : nil
    end

    def budget_dollars=(value)
      self.budget_cents = value.blank? ? 0 : (value.to_f * 100).round
    end

    def monthly_spend_cents
      return @monthly_spend_cents if defined?(@monthly_spend_cents)
      @monthly_spend_cents =
        if preloaded_monthly_spend_cents
          preloaded_monthly_spend_cents
        elsif budget_configured?
          period_start = Date.current.beginning_of_month.beginning_of_day
          runs.where(created_at: period_start..).sum(:cost_cents)
        else
          0
        end
    end

    def budget_remaining_cents
      return nil unless budget_configured?
      [ budget_cents - monthly_spend_cents, 0 ].max
    end

    def budget_utilization
      return 0.0 unless budget_configured?
      [ (monthly_spend_cents.to_f / budget_cents * 100), 100.0 ].min.round(1)
    end

    def budget_exhausted?
      budget_configured? && monthly_spend_cents >= budget_cents
    end

    def budget_alert_threshold?
      budget_configured? && budget_utilization >= 80.0
    end
  end
end
