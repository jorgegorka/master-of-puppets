module Runs
  module Costing
    extend ActiveSupport::Concern

    def add_cost(cents)
      return if cents.to_i.zero?
      with_lock do
        increment!(:cost_cents, cents.to_i)
      end
      enforce_budget!
    end

    def enforce_budget!
      return unless column.budget_configured?
      raise Run::BudgetExceeded, "Column ##{column_id} budget exceeded" if column.budget_exhausted?
    end
  end
end
