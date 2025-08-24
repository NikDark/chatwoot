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
    message_data = @event_data['object']['message']
    group_id = @event_data['group_id']
    
    channel = Channel::Vk.find_by(group_id: group_id)
    return unless channel

    return if channel.reauthorization_required?
    
    Vk::MessageTextService.new(message_data, channel).perform
  end

  def process_outgoing_message
    # Handle outgoing message confirmations
    # Update message status, handle delivery receipts
    message_data = @event_data['object']['message']
    group_id = @event_data['group_id']
    
    channel = Channel::Vk.find_by(group_id: group_id)
    return unless channel

    # Find and update message status if needed
    Rails.logger.info("VK outgoing message confirmation: #{message_data['id']}")
  end
end