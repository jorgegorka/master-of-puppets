module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      logger.add_tags("ActionCable", "User #{current_user.id}")
    end

    private
      def find_verified_user
        session = Session.find_by(id: cookies.signed[:session_id])
        if session.nil? || session.expired?
          session&.destroy
          reject_unauthorized_connection
        end
        session.user
      end
  end
end
