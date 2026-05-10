module Projects
  module Spend
    extend ActiveSupport::Concern

    def preload_monthly_spend(columns)
      period_start = Date.current.beginning_of_month.beginning_of_day
      spend_by_column = Run.where(column_id: columns.select(:id))
                           .where(created_at: period_start..)
                           .group(:column_id)
                           .sum(:cost_cents)
      columns.each { |c| c.preloaded_monthly_spend_cents = spend_by_column[c.id] || 0 }
      spend_by_column.values.sum
    end
  end
end
