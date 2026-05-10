module Columns
  module Broadcasting
    extend ActiveSupport::Concern

    included do
      after_commit :broadcast_board_update, on: %i[create update]
      after_destroy_commit :broadcast_board_remove
    end

    def broadcast_stream
      "project_#{project_id}_board"
    end

    private

    def broadcast_board_update
      Turbo::StreamsChannel.broadcast_replace_to(
        broadcast_stream,
        target: "kanban-column-#{id}",
        partial: "tasks/column",
        locals: { column: self, tasks: tasks.to_a }
      )
    rescue ActionView::Template::Error => e
      Rails.logger.warn("[Column##{id}] board broadcast failed: #{e.message}")
    end

    def broadcast_board_remove
      Turbo::StreamsChannel.broadcast_remove_to(
        broadcast_stream,
        target: "kanban-column-#{id}"
      )
    end
  end
end
