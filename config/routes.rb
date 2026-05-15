Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes (uncomment when ready; Phase 7)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "dashboard#show"

  resource :session, only: %i[new create destroy]

  resources :chat_sessions, path: "chat" do
    scope module: :chat_sessions do
      resources :messages, only: %i[create]
      resources :forks,    only: %i[create]
      resource  :archive,  only: %i[create destroy]
      resource  :pin,      only: %i[create destroy]
    end
  end

  resource :settings, only: %i[show update] do
    scope module: :settings do
      resources :providers, only: %i[index show update] do
        scope module: :providers do
          resource :test, only: %i[create]
        end
      end
    end
  end
end
