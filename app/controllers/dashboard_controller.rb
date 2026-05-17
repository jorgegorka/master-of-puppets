class DashboardController < ApplicationController
  def show
    @dashboard = Dashboard::Show.new(Current.user)
  end
end
