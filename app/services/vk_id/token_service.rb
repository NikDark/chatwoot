class VkId::TokenService
  include HTTParty
  
  base_uri 'https://id.vk.com'
  
  def initialize(user)
    @user = user
    @vk_data = user.custom_attributes&.dig('vk_id') || {}
  end

  # Refresh access token using refresh token
  # According to VK ID OAuth 2.1 documentation: POST /oauth2/auth?grant_type=refresh_token
  def refresh_token!
    return false unless refresh_token.present?

    response = self.class.post('/oauth2/auth', {
      body: {
        grant_type: 'refresh_token',
        refresh_token: refresh_token,
        client_id: ENV['VK_ID_CLIENT_ID'],
        client_secret: ENV['VK_ID_CLIENT_SECRET']
      },
      headers: {
        'Content-Type' => 'application/x-www-form-urlencoded'
      }
    })

    if response.success?
      update_tokens(response.parsed_response)
      true
    else
      Rails.logger.error("VK ID token refresh failed: #{response.body}")
      false
    end
  rescue StandardError => e
    Rails.logger.error("VK ID token refresh error: #{e.message}")
    false
  end

  # Get user info using current access token
  # According to VK ID OAuth 2.1 documentation: GET /oauth2/user_info
  def get_user_info
    return nil unless access_token.present?

    response = self.class.get('/oauth2/user_info', {
      headers: {
        'Authorization' => "Bearer #{access_token}"
      }
    })

    if response.success?
      response.parsed_response
    else
      Rails.logger.error("VK ID user info request failed: #{response.body}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("VK ID user info error: #{e.message}")
    nil
  end

  # Check if access token is expired
  def token_expired?
    return true unless expires_at.present?
    
    Time.current >= Time.at(expires_at)
  end

  # Get valid access token (refresh if needed)
  def valid_access_token
    if token_expired?
      refresh_token! ? access_token : nil
    else
      access_token
    end
  end

  # Revoke all tokens
  def revoke_tokens!
    return false unless access_token.present?

    response = self.class.post('/oauth2/revoke', {
      body: {
        token: access_token,
        client_id: ENV['VK_ID_CLIENT_ID'],
        client_secret: ENV['VK_ID_CLIENT_SECRET']
      },
      headers: {
        'Content-Type' => 'application/x-www-form-urlencoded'
      }
    })

    if response.success?
      clear_tokens!
      true
    else
      Rails.logger.error("VK ID token revocation failed: #{response.body}")
      false
    end
  rescue StandardError => e
    Rails.logger.error("VK ID token revocation error: #{e.message}")
    false
  end

  private

  def access_token
    @vk_data['access_token']
  end

  def refresh_token
    @vk_data['refresh_token']
  end

  def expires_at
    @vk_data['expires_at']
  end

  def update_tokens(token_response)
    vk_attributes = @user.custom_attributes || {}
    vk_attributes['vk_id'] = @vk_data.merge({
      'access_token' => token_response['access_token'],
      'refresh_token' => token_response['refresh_token'],
      'expires_at' => (Time.current + token_response['expires_in'].to_i.seconds).to_i,
      'updated_at' => Time.current.iso8601
    })

    @user.update!(custom_attributes: vk_attributes)
    @vk_data = vk_attributes['vk_id']
  end

  def clear_tokens!
    vk_attributes = @user.custom_attributes || {}
    vk_attributes.delete('vk_id')
    @user.update!(custom_attributes: vk_attributes)
    @vk_data = {}
  end
end