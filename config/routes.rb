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

  resource :memory, controller: "memory", only: [ :show ] do
    scope module: :memory do
      resources :files,    only: %i[show update create destroy],
                constraints: { id: %r{[^?]+} }, defaults: { format: :html }
      resources :searches, only: %i[create]
    end
  end

  resource :files, controller: "files", only: [ :show ] do
    scope module: :files do
      resources :nodes, only: %i[index show create update destroy],
                constraints: { id: %r{[^?]+} }, defaults: { format: :html }
    end
  end

  resources :skills, only: %i[index show update] do
    scope module: :skills do
      resource :installation, only: %i[create destroy]
      resource :enablement,   only: %i[create destroy]
    end
  end

  resources :terminals, only: %i[index show new create destroy]

  resources :scheduled_jobs, path: "jobs" do
    collection do
      # Read-only, stateless preview helper (no resource being mutated) —
      # the rails-patterns rule against custom action routes targets
      # state-changing routes; this is fine.
      get :cron_preview
    end
    scope module: :scheduled_jobs do
      resource  :pause, only: %i[create destroy]
      resources :runs,  only: %i[index show create]
    end
  end

  resources :mcp_servers do
    scope module: :mcp_servers do
      resource :test,      only: %i[create]
      resource :discovery, only: %i[create]
    end
  end
end
