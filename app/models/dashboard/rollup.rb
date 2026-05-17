class Dashboard::Rollup
  DEFAULT_DAYS = 14

  def initialize(scope: Message.all, days: DEFAULT_DAYS)
    @scope = scope.where(status: :completed).where(messages: { created_at: days.days.ago.. })
  end

  def tokens_by_day
    @scope
      .group(Arel.sql("date(messages.created_at)"))
      .pluck(
        Arel.sql("date(messages.created_at)"),
        Arel.sql("COALESCE(SUM(messages.prompt_tokens + messages.completion_tokens), 0)"),
        Arel.sql("COALESCE(SUM(messages.cost_usd), 0)")
      )
      .map { |day, tokens, cost| { day: day, tokens: tokens.to_i, cost_usd: cost } }
  end

  def cost_by_model
    @scope
      .group(:model)
      .sum(:cost_usd)
      .transform_values(&:to_d)
  end

  def cost_by_session(limit: 10)
    @scope
      .group(:chat_session_id)
      .order(Arel.sql("SUM(cost_usd) DESC"))
      .limit(limit)
      .sum(:cost_usd)
  end
end
