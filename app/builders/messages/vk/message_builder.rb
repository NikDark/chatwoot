class Messages::Vk::MessageBuilder
  attr_reader :message_data, :inbox, :contact_inbox

  def initialize(message_data, inbox, contact_inbox)
    @message_data = message_data
    @inbox = inbox
    @contact_inbox = contact_inbox
  end

  def perform
    return if message_data['text'].blank?

    @message = Message.create!(message_params)

    # Mark previous outgoing messages as read when user replies
    mark_previous_messages_as_read

    @message
  end

  private

  def mark_previous_messages_as_read
    # Mark all previous outgoing messages as read when user replies
    # This is a common pattern when read receipts are not available
    return unless conversation

    conversation.messages
                .where(message_type: 'outgoing')
                .where(status: %w[sent delivered])
                .where('created_at < ?', Time.current)
                .find_each do |message|
      Messages::StatusUpdateService.new(message, 'read').perform
    end
  end

  def conversation
    @conversation ||= find_or_create_conversation
  end

  def find_or_create_conversation
    # Try to find existing conversation
    existing_conversation = if @inbox.lock_to_single_conversation
                             @contact_inbox.conversations.last
                           else
                             @contact_inbox.conversations.where.not(status: :resolved).last
                           end

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
      message_type: :incoming,
      content: message_data['text'],
      source_id: message_data['id'].to_s,
      sender_type: 'Contact',
      sender_id: @contact_inbox.contact.id,
      external_source_ids: { 'vk_message_id' => message_data['id'].to_s }
    }
  end
end
