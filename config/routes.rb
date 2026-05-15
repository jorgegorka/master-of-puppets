Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes (uncomment when ready; Phase 7)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "dashboard#show"

  resource :session, only: %i[new create destroy]
end
