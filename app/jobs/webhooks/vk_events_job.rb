class Webhooks::VkEventsJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  SUPPORTED_EVENTS = [:message_new, :message_reply].freeze

  def perform(event_data)
    @event_data = event_data.with_indifferent_access

    group_id = @event_data['group_id']
    key = format(::Redis::Alfred::VK_MESSAGE_MUTEX, group_id: group_id)

    with_lock(key) do
      process_event
    end
  end

  private

  def process_event
    Rails.logger.info("Processing VK event: #{@event_data['type']} for group #{@event_data['group_id']}")
    Rails.logger.debug("VK event data: #{@event_data.inspect}")

    case @event_data['type']
    when 'message_new'
      process_incoming_message
    when 'message_reply'
      process_outgoing_message
    else
      Rails.logger.info("Unprocessed VK event: #{@event_data['type']}")
    end
  end

  def process_incoming_message
    # For message_new events, the message data is usually in object.message
    # But for some events it might be directly in object
    message_data = @event_data['object']['message'] || @event_data['object']
    group_id = @event_data['group_id']

    Rails.logger.info("VK incoming message data: #{message_data.inspect}")

    channel = Channel::Vk.find_by(group_id: group_id)
    unless channel
      Rails.logger.warn("VK channel not found for group_id: #{group_id}")
      return
    end

    if channel.reauthorization_required?
      Rails.logger.warn("VK channel requires reauthorization: #{group_id}")
      return
    end

    unless message_data&.is_a?(Hash)
      Rails.logger.warn("VK invalid message data: #{message_data}")
      return
    end

    Vk::MessageTextService.new(message_data, channel).perform
  end

  def process_outgoing_message
    # Handle outgoing message replies - create them as outgoing messages
    message_data = @event_data['object']
    group_id = @event_data['group_id']

    Rails.logger.info("VK outgoing message data structure: #{message_data.inspect}")

    channel = Channel::Vk.find_by(group_id: group_id)
    return unless channel

    return unless message_data&.is_a?(Hash)

    # For message_reply events, we need to create outgoing messages
    # Skip if message is from external user (not from group admin)
    Vk::OutgoingMessageService.new(message_data, channel).perform
    # return unless message_data['from_id'] && message_data['from_id'] != message_data['peer_id']

    # Create outgoing message for admin replies
  end
end
