module VkConcern
  extend ActiveSupport::Concern

  def vk_authorization_url(state)
    params = {
      client_id: vk_app_id,
      redirect_uri: vk_callback_url,
      scope: 'messages,groups',
      response_type: 'code',
      state: state,
      v: GlobalConfigService.load('VK_API_VERSION', '5.131')
    }
    
    "https://oauth.vk.com/authorize?#{params.to_query}"
  end

  private

  def vk_app_id
    GlobalConfigService.load('VK_APP_ID', '')
  end

  def vk_app_secret
    GlobalConfigService.load('VK_APP_SECRET', '')
  end

  def vk_callback_url
    Rails.application.routes.url_helpers.vk_callback_url(
      protocol: Rails.application.config.force_ssl ? 'https' : 'http',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end
end