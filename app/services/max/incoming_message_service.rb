class Max::IncomingMessageService
  include ::FileTypeHelper
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless private_message?

    set_contact
    set_conversation

    @message = @conversation.messages.build(
      content: params.dig(:message, :text),
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: params.dig(:message, :message_id).to_s
    )
    @message.save!
  end

  private

  def private_message?
    params[:message].present?
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: params.dig(:message, :from, :id),
      inbox: inbox,
      contact_attributes: {
        name: [params.dig(:message, :from, :first_name), params.dig(:message, :from, :last_name)].compact.join(' ')
      }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def set_conversation
    @conversation = @contact_inbox.conversations.first
    return if @conversation

    @conversation = ::Conversation.create!(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: { chat_id: params.dig(:message, :chat, :id) }
    )
  end
end

