# Load custom VK ID strategy
require_relative '../../lib/omniauth/strategies/vk_id'

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }

  # VK ID OAuth 2.1 provider
  provider :vk_id, ENV.fetch('VK_ID_CLIENT_ID', nil), ENV.fetch('VK_ID_CLIENT_SECRET', nil), {
    scope: 'email'
  }
end
