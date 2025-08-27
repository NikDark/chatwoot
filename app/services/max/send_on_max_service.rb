class Max::SendOnMaxService
  pattr_initialize [:message!]

  def perform
    return if message.outgoing? && message.private
    channel = message.conversation.inbox.channel
    return unless channel.is_a?(Channel::Max)

    external_id = channel.send_message_on_max(message)
    message.update!(content_attributes: message.content_attributes.merge(external_id: external_id)) if external_id
  end
end

