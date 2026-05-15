class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current
  before_action :require_sign_in

  private
    def set_current
      Current.session    = Session.find_by(id: cookies.signed[:session_id])
      Current.user       = Current.session&.user
      Current.ip_address = request.remote_ip
      Current.user_agent = request.user_agent
    end

    def require_sign_in
      unless Current.user
        redirect_to new_session_path
      end
    end

    # Subclasses opt-in with `before_action :require_admin`. The User#role
    # enum and the bootstrap-to-admin callback in User make this gate the
    # default seat for privileged surfaces (Settings::Providers* in Phase 1).
    def require_admin
      redirect_to root_path, alert: "Admin only." unless Current.user&.admin?
    end
end
