class Vk::SendOnVkService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Vk
  end

  def perform_reply
    send_text_message if message.content.present?
    send_attachments if message.attachments.present?
  rescue StandardError => e
    handle_vk_error(e)
  end

  def send_text_message
    response = HTTParty.post(
      'https://api.vk.com/method/messages.send',
      body: {
        peer_id: contact.get_source_id(inbox.id),
        message: message.content,
        random_id: generate_random_id,
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    handle_send_response(response)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_attachment(attachment)
    end
  end

  def send_attachment(attachment)
    # Upload attachment to VK and send
    case attachment.file_type
    when 'image'
      send_photo_attachment(attachment)
    when 'file'
      send_document_attachment(attachment)
    else
      Rails.logger.warn("Unsupported VK attachment type: #{attachment.file_type}")
    end
  end

  def send_photo_attachment(attachment)
    # VK photo upload process is complex, implement as needed
    Rails.logger.info("Sending VK photo attachment: #{attachment.id}")
    # For now, send as file URL in message
    send_text_message_with_attachment(attachment)
  end

  def send_document_attachment(attachment)
    # VK document upload process
    Rails.logger.info("Sending VK document attachment: #{attachment.id}")
    # For now, send as file URL in message
    send_text_message_with_attachment(attachment)
  end

  def send_text_message_with_attachment(attachment)
    attachment_message = "📎 #{attachment.file.filename}: #{attachment.download_url}"
    
    response = HTTParty.post(
      'https://api.vk.com/method/messages.send',
      body: {
        peer_id: contact.get_source_id(inbox.id),
        message: attachment_message,
        random_id: generate_random_id,
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    handle_send_response(response)
  end

  def handle_send_response(response)
    if response.success?
      parsed_response = response.parsed_response
      
      if parsed_response['error']
        handle_api_error(parsed_response['error'])
      elsif parsed_response['response']
        message.update!(source_id: parsed_response['response'].to_s)
        Messages::StatusUpdateService.new(message, 'sent').perform
      end
    else
      Messages::StatusUpdateService.new(message, 'failed', 'HTTP Error').perform
    end
  end

  def handle_api_error(error)
    error_code = error['error_code']
    error_msg = error['error_msg']
    
    case error_code
    when 5 # User authorization failed
      channel.authorization_error!
    when 7 # Permission to perform this action is denied
      Rails.logger.error("VK permission denied: #{error_msg}")
    when 901 # Can't send messages for users without permission
      Rails.logger.warn("VK user blocked messages: #{error_msg}")
    end
    
    Messages::StatusUpdateService.new(message, 'failed', error_msg).perform
  end

  def generate_random_id
    Random.rand(2**31)
  end

  def handle_vk_error(error)
    Rails.logger.error("VK send error: #{error.message}")
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end
end