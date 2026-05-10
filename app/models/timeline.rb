class Timeline
  DEFAULT_LIMIT = 25

  attr_reader :limit

  def self.parse_cursor(value)
    Time.iso8601(value) if value.present?
  rescue ArgumentError
    nil
  end

  def initialize(sources:, before: nil, limit: DEFAULT_LIMIT)
    @sources = sources
    @before = before
    @limit = limit
  end

  def entries
    load_entries
    @entries
  end

  def next_cursor
    entries.last&.created_at
  end

  def more_available?
    load_entries
    @more_available
  end

  private

  def load_entries
    return if defined?(@entries)
    merged = @sources.flat_map { |relation| fetch(relation) }
                     .sort_by { |entry| [ -entry.created_at.to_f, -entry.id.to_i ] }
    @more_available = merged.size > @limit
    @entries = merged.first(@limit)
  end

  def fetch(relation)
    scope = relation.order(created_at: :desc).limit(@limit + 1)
    scope = scope.where(scope.arel_table[:created_at].lt(@before)) if @before
    scope.to_a
  end
end
