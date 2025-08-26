module Vk::IntegrationHelper
  # Generates a simple random state parameter for VK OAuth (as per official docs)
  #
  # @param account_id [Integer] The account ID to associate with the state
  # @param code_verifier [String] The PKCE code_verifier to store temporarily
  # @return [String] The generated state string (32+ chars random)
  def generate_vk_state(account_id, code_verifier)
    # Ensure account_id is an integer
    account_id = account_id.to_i if account_id.respond_to?(:to_i)

    # Generate random state (32+ chars as per VK docs)
    state = SecureRandom.urlsafe_base64(32).tr('+/', '-_').gsub('=', '')

    # Store account_id and code_verifier in Redis with 1 hour expiry
    redis_key = format(Redis::RedisKeys::VK_OAUTH_STATE_KEY, state: state)
    data = {
      account_id: account_id,
      code_verifier: code_verifier,
      created_at: Time.current.to_i
    }

    Redis::Alfred.setex(redis_key, data.to_json, 3600) # 1 hour expiry

    Rails.logger.info("VK: Generated state #{state[0..10]}... for account #{account_id}")
    state
  end

  # Retrieves account_id and code_verifier from VK state parameter
  #
  # @param state [String] The state parameter from VK callback
  # @return [Hash, nil] Hash with :account_id and :code_verifier, or nil if invalid/expired
  def retrieve_vk_oauth_data(state)
    return if state.blank?

    redis_key = format(Redis::RedisKeys::VK_OAUTH_STATE_KEY, state: state)
    data_json = Redis::Alfred.get(redis_key)

    return if data_json.blank?

    data = JSON.parse(data_json, symbolize_names: true)

    # Clean up Redis key after use (one-time use)
    Redis::Alfred.delete(redis_key)

    Rails.logger.info("VK: Retrieved data for state #{state[0..10]}... - account_id: #{data[:account_id]}")
    data
  rescue JSON::ParserError => e
    Rails.logger.error("VK: Failed to parse OAuth data from Redis: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.error("VK: Unexpected error retrieving OAuth data: #{e.message}")
    nil
  end

  # Helper method to get OAuth data without deleting from Redis (for error handling)
  #
  # @param state [String] The state parameter from VK callback
  # @return [Hash, nil] Hash with :account_id and :code_verifier, or nil if invalid/expired
  def peek_vk_oauth_data(state)
    return if state.blank?

    redis_key = format(Redis::RedisKeys::VK_OAUTH_STATE_KEY, state: state)
    data_json = Redis::Alfred.get(redis_key)

    return if data_json.blank?

    JSON.parse(data_json, symbolize_names: true)
  rescue JSON::ParserError => e
    Rails.logger.error("VK: Failed to parse OAuth data from Redis: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.error("VK: Unexpected error peeking OAuth data: #{e.message}")
    nil
  end

  private

  def vk_app_secret
    @vk_app_secret ||= GlobalConfigService.load('VK_APP_SECRET', nil)
  end
end
