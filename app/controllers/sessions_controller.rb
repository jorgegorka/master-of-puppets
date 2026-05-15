class SessionsController < ApplicationController
  skip_before_action :require_sign_in, only: %i[new create]

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)
    if user&.authenticate(params[:password])
      session = user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
      cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :strict, secure: Rails.env.production? }
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    Current.session&.destroy
    cookies.delete(:session_id)
    redirect_to new_session_path
  end
end
