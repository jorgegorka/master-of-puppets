class SettingsController < ApplicationController
  def show
    @user_setting = Current.user.user_setting
  end

  def update
    Current.user.user_setting.update!(user_setting_params)

    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Saved." }
      format.json { head :no_content }
    end
  end

  private
    def user_setting_params
      params.expect(user_setting: %i[theme accent editor_font_size sidebar_collapsed notifications_enabled usage_threshold])
    end
end
