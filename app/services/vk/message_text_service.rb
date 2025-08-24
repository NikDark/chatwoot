class Vk::MessageTextService < Vk::BaseService
  attr_reader :message_data

  def initialize(message_data, channel)
    @message_data = message_data
    super(channel)
  end

  def perform
    return unless valid_message?
    
    ensure_contact_inbox
    create_message if @contact_inbox
  end

  private

  def valid_message?
    message_data['from_id'].present? && 
      message_data['text'].present? &&
      message_data['from_id'] != channel.group_id.to_i # Skip messages from the group itself
  end

  def ensure_contact_inbox
    vk_user_id = message_data['from_id']
    
    @contact_inbox = @inbox.contact_inboxes.find_by(source_id: vk_user_id.to_s)
    
    if @contact_inbox.blank?
      user_info = fetch_user_info(vk_user_id)
      @contact_inbox = channel.create_contact_inbox(vk_user_id, user_info[:name])
    end
  end

  def fetch_user_info(user_id)
    response = HTTParty.get(
      'https://api.vk.com/method/users.get',
      query: {
        user_ids: user_id,
        fields: 'first_name,last_name,photo_200',
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    if response.success? && response.parsed_response['response'].present?
      user = response.parsed_response['response'].first
      {
        name: "#{user['first_name']} #{user['last_name']}".strip,
        avatar_url: user['photo_200']
      }
    else
      handle_user_fetch_error(response, user_id)
      { name: "VK User #{user_id}" }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch VK user info: #{e.message}")
    { name: "VK User #{user_id}" }
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