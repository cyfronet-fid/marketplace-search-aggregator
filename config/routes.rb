# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get 'services', to: 'services#index'
      post 'aggregated_data/custom', to: 'aggregated_data#custom_aggregate'
      
      # Health check endpoint
      get 'health', to: proc { [200, {}, ['OK']] }
    end
  end
  
  # Redirect root to API documentation or health check
  root to: redirect('/api/v1/health')
end