class Messages::Vk::MessageBuilder
  attr_reader :message_data, :inbox, :contact_inbox

  def initialize(message_data, inbox, contact_inbox)
    @message_data = message_data
    @inbox = inbox
    @contact_inbox = contact_inbox
  end

  def perform
    return if message_data['text'].blank?
    
    @message = conversation.messages.create!(message_params)
    @message
  end

  private

  def conversation
    @conversation ||= @contact_inbox.conversation || create_conversation
  end

  def create_conversation
    @contact_inbox.create_conversation(
      account: @inbox.account,
      inbox: @inbox,
      contact: @contact_inbox.contact
    )
  end

  def message_params
    {
      account: @inbox.account,
      inbox: @inbox,
      message_type: :incoming,
      content: message_data['text'],
      source_id: message_data['id'].to_s,
      contact: @contact_inbox.contact,
      sender: @contact_inbox.contact,
      external_source_id_key: 'vk_message_id'
    }
  end
end