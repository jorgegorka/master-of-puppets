Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resource :registration, only: [ :new, :create ]

  resource :settings, only: [ :show, :update ]

  namespace :onboarding do
    resource :project,    only: [ :new, :create ]
    resource :template,   only: [ :new, :create ]
    resource :adapter,    only: [ :new, :create ]
    resource :completion, only: [ :new, :create ]
  end

  resources :projects, only: [ :index, :new, :create, :edit, :update ] do
    resource :switch, only: [ :create ], module: :projects, controller: "switches"
  end

  resources :invitations, only: [ :index, :new, :create ]
  resources :invitation_acceptances, only: [ :show, :update ], param: :token

  resources :columns do
    resource  :activity, only: [ :create, :destroy ], module: :columns
    resources :runs, only: [ :index, :show ], module: :columns
    resource  :api_token, only: [ :update ], module: :columns
    resources :column_skills, only: [ :create, :destroy ]
  end

  resources :runs, only: [ :show ] do
    resource :cancellation, only: [ :create ], module: :runs
  end

  resources :skills do
    resources :skill_documents, only: [ :create, :destroy ]
  end

  resources :documents
  resources :document_tags, only: [ :index, :create, :destroy ]

  resources :tasks do
    resources :task_documents, only: [ :create, :destroy ]
    resources :messages, only: [ :create ]
    resource  :transition, only: [ :create ], module: :tasks
    resource  :approval,   only: [ :update ], module: :tasks
    resource  :rejection,  only: [ :update ], module: :tasks
    scope module: :tasks do
      resources :timeline_entries, only: [ :index ]
    end
    collection do
      resource :bulk_update, only: [ :create, :destroy ], module: :tasks
    end
  end

  resources :goals do
    resource :recurrence, module: :goals, only: [ :destroy ]
  end

  resources :notifications, only: [ :index ] do
    member do
      patch :mark_read
    end
    collection do
      post :mark_all_read
    end
  end

  resources :audit_logs, only: [ :index ]

  resources :config_versions, only: [ :index, :show ] do
    member do
      post :rollback
    end
  end

  resource :dashboard, only: [ :show ], controller: "dashboard"

  get "docs", to: "docs#index", as: :docs
  namespace :documentation, path: "docs" do
    resources :projects, only: [ :index ]
    resources :adapters, only: [ :index ]
    resources :tasks, only: [ :index ]
    resources :skills, only: [ :index ]
  end
  get "docs/*path", to: "docs#show", as: :docs_page

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
