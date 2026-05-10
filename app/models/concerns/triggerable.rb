module Triggerable
  extend ActiveSupport::Concern

  private

  # Substring matching to support multi-word column names (e.g. "@In Progress").
  # Returns Column records mentioned in `text` for the given project.
  def detect_mentions(text, project)
    return [] if text.blank? || project.nil?
    return [] unless text.include?("@")

    text_downcased = text.downcase
    matched_ids = project.columns.pluck(:id, :name).filter_map do |id, name|
      id if text_downcased.include?("@#{name.downcase}")
    end

    matched_ids.any? ? project.columns.where(id: matched_ids).to_a : []
  end
end
