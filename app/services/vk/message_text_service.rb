class Vk::MessageTextService < Vk::BaseService
  attr_reader :message_data

  def initialize(message_data, channel)
    @message_data = message_data
    super(channel)
  end

  def perform
    Rails.logger.info("VK MessageTextService processing: from_id=#{message_data['from_id']}, peer_id=#{message_data['peer_id']}, text=#{message_data['text']}")

    unless valid_message?
      Rails.logger.info("VK message validation failed")
      return
    end

    ensure_contact_inbox
    if @contact_inbox
      create_message
      Rails.logger.info("VK message created successfully")
    else
      Rails.logger.warn("VK contact inbox not found/created")
    end
  end

  private

  def valid_message?
    message_data['from_id'].present? &&
      message_data['text'].present? &&
      !group_message?
  end

  def group_message?
    # Skip messages from the group itself (when group posts to its own wall)
    # But allow admin messages to users (when admin replies to user)
    group_id = channel.group_id.to_i
    from_id = message_data['from_id'].to_i
    peer_id = message_data['peer_id'].to_i

    # If from_id is negative, it's usually a group ID
    return true if from_id < 0 && from_id.abs == group_id

    # If from_id equals group_id and peer_id equals group_id, it's a group posting to itself
    return true if from_id == group_id && peer_id == group_id

    false
  end

  def ensure_contact_inbox
    vk_user_id = message_data['from_id']

    @contact_inbox = @inbox.contact_inboxes.find_by(source_id: vk_user_id.to_s)

    if @contact_inbox.blank?
      user_info = fetch_user_info(vk_user_id)
      @contact_inbox = channel.create_contact_inbox(vk_user_id, user_info)
    end
  end

  def fetch_user_info(user_id)
    # Try new VK ID API endpoint first
    user_info = fetch_user_info_from_vk_id(user_id)
    return user_info if user_info.present?

    # Fallback to old VK API for backward compatibility
    fetch_user_info_legacy(user_id)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch VK user info: #{e.message}")
    { name: "VK User #{user_id}" }
  end

  def fetch_user_info_from_vk_id(user_id)
    response = HTTParty.get(
      'https://id.vk.com/oauth2/user_info',
      headers: {
        'Authorization' => "Bearer #{channel.access_token}"
      }
    )

    if response.success? && response.parsed_response['user'].present?
      user = response.parsed_response['user']

      # Check if this is the user we're looking for
      return nil unless user['user_id'].to_s == user_id.to_s

      {
        name: "#{user['first_name']} #{user['last_name']}".strip,
        avatar_url: user['avatar'],
        phone: user['phone'],
        email: user['email'],
        sex: user['sex'],
        verified: user['verified'],
        birthday: user['birthday']
      }
    else
      nil
    end
  end

  def fetch_user_info_legacy(user_id)
    response = HTTParty.get(
      'https://api.vk.com/method/users.get',
      query: {
        user_ids: user_id,
        fields: 'first_name,last_name,photo_200,sex,verified,bdate',
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )

    if response.success? && response.parsed_response['response'].present?
      user = response.parsed_response['response'].first
      {
        name: "#{user['first_name']} #{user['last_name']}".strip,
        avatar_url: user['photo_200'],
        sex: user['sex'],
        verified: user['verified'],
        birthday: user['bdate']
      }
    else
      handle_user_fetch_error(response, user_id)
      { name: "VK User #{user_id}" }
    end
  end

  def handle_user_fetch_error(response, user_id)
    error = response.parsed_response&.dig('error')
    return unless error

    error_code = error['error_code']

    # Handle token expiration
    if error_code == 5 # User authorization failed
      channel.authorization_error!
    end

    Rails.logger.error("VK user fetch error for user #{user_id}: #{error['error_msg']} (Code: #{error_code})")
  end

  def create_message
    Messages::Vk::MessageBuilder.new(message_data, @inbox, @contact_inbox).perform
  end
end
