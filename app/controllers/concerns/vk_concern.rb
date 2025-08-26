module VkConcern
  extend ActiveSupport::Concern

  def vk_authorization_url(state)
    params = {
      response_type: 'code',
      client_id: vk_app_id,
      redirect_uri: vk_callback_url,
      scope: 'groups',
      state: state,
    }

    "https://oauth.vk.com/authorize?#{params.to_query}"
  end

  def vk_groups_authorization_url(state, group_ids)
    params = {
      response_type: 'code',
      client_id: vk_app_id,
      redirect_uri: vk_groups_callback_url,
      group_ids: group_ids.join(','),
      scope: 'messages,manage',
      state: state,
      v: GlobalConfigService.load('VK_API_VERSION', '5.131')
    }

    "https://oauth.vk.com/authorize?#{params.to_query}"
  end

  def generate_pkce_parameters
    # Generate code_verifier (43-128 characters, a-z, A-Z, 0-9, _, -)
    code_verifier = SecureRandom.urlsafe_base64(96).tr('+/', '-_')[0...128]

    # Generate code_challenge (SHA256 hash of code_verifier, base64url encoded)
    code_challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier)
    ).tr('+/', '-_').gsub('=', '')

    {
      code_verifier: code_verifier,
      code_challenge: code_challenge
    }
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
      protocol: Rails.application.config.force_ssl ? 'https' : 'https',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end

  def vk_groups_callback_url
    Rails.application.routes.url_helpers.vk_groups_callback_url(
      protocol: Rails.application.config.force_ssl ? 'https' : 'https',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end
end
