module Triggerable
  extend ActiveSupport::Concern

  private

  # Substring matching to support multi-word column names (e.g. "@In Progress").
  # Returns Column records mentioned in `text` for the given project.
  def detect_mentions(text, project)
    return [] if text.blank? || project.nil?
    return [] unless text.include?("@")

    text_downcased = text.downcase
    project.columns.select { |c| text_downcased.include?("@#{c.name.downcase}") }
  end
end
