class Messages::Vk::OutgoingMessageBuilder
  attr_reader :message_data, :inbox, :contact_inbox

  def initialize(message_data, inbox, contact_inbox)
    @message_data = message_data
    @inbox = inbox
    @contact_inbox = contact_inbox
  end

  def perform
    return if message_data['text'].blank?

    # Check if message already exists to avoid duplicates
    return if message_already_exists?

    @message = Message.create!(message_params)
    @message
  end

  private

  def message_already_exists?
    conversation.messages.exists?(
      source_id: message_data['id'].to_s,
      message_type: :outgoing
    )
  end

  def conversation
    @conversation ||= find_conversation
  end

  def find_conversation
    # Find existing conversation for outgoing messages
    existing_conversation = if @inbox.lock_to_single_conversation
                             @contact_inbox.conversations.last
                           else
                             @contact_inbox.conversations.where.not(status: :resolved).last
                           end

    # For outgoing messages, we should have existing conversation
    # If not, create one
    return existing_conversation if existing_conversation.present?

    # Create new conversation if none exists
    Conversation.create!(
      account: @inbox.account,
      inbox: @inbox,
      contact: @contact_inbox.contact,
      contact_inbox: @contact_inbox
    )
  end

  def message_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      conversation_id: conversation.id,
      message_type: :outgoing,
      content: message_data['text'],
      source_id: message_data['id'].to_s,
      sender_type: 'User',
      sender_id: find_admin_user_id,
      external_source_ids: { 'vk_message_id' => message_data['id'].to_s }
    }
  end

  def find_admin_user_id
    # Try to find a user in this account who could have sent this message
    # For now, use the first admin/agent in the account
    # In the future, we could try to match by VK admin_author_id
    account_user = @inbox.account.account_users.where(role: ['administrator', 'agent']).first
    account_user&.user_id
  end
end
