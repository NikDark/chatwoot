class Vk::OutgoingMessageService < Vk::BaseService
  attr_reader :message_data

  def initialize(message_data, channel)
    @message_data = message_data
    super(channel)
  end

  def perform
    return unless valid_outgoing_message?

    ensure_contact_inbox
    create_outgoing_message if @contact_inbox
  end

  private

  def valid_outgoing_message?
    message_data['peer_id'].present? &&
      message_data['text'].present? &&
      message_data['from_id'].present? &&
      admin_reply?
  end

  def admin_reply?
    from_id = message_data['from_id'].to_i
    peer_id = message_data['peer_id'].to_i
    group_id = channel.group_id.to_i

    Rails.logger.info("VK admin_reply check: from_id=#{from_id}, peer_id=#{peer_id}, group_id=#{group_id}")

    # Skip messages from the group itself (these are from Chatwoot)
    if from_id == -group_id
      Rails.logger.info("VK skipping group message (from Chatwoot)")
      return false
    end

    # Check if this is admin replying to user
    # from_id should be an admin (positive ID) and peer_id should be user (positive ID)
    # and they should be different (admin writing to user)
    # We also check for admin_author_id which is present when admin writes directly
    has_admin_author = message_data['admin_author_id'].present?
    is_admin_to_user = from_id > 0 && peer_id > 0 && from_id != peer_id

    result = has_admin_author || is_admin_to_user
    Rails.logger.info("VK admin_reply result: #{result} (has_admin_author: #{has_admin_author}, is_admin_to_user: #{is_admin_to_user})")
    result
  end

  def ensure_contact_inbox
    vk_user_id = message_data['peer_id']

    @contact_inbox = @inbox.contact_inboxes.find_by(source_id: vk_user_id.to_s)

    if @contact_inbox.blank?
      # If no contact inbox exists, create one so that outgoing replies from VK admins
      # appear in Chatwoot even if the user hasn't messaged first.
      Rails.logger.info("VK outgoing message: creating contact inbox for user #{vk_user_id}")
      @contact_inbox = channel.create_contact_inbox(vk_user_id, {})
    end
  end

  def create_outgoing_message
    Messages::Vk::OutgoingMessageBuilder.new(message_data, @inbox, @contact_inbox).perform
  end
end
