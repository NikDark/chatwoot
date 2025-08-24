class Webhooks::VkController < ActionController::API
  before_action :verify_signature, except: [:verify]

  def verify
    render plain: params['hub.challenge'] if valid_verify_token?
  end

  def events
    Rails.logger.info('VK webhook received events')
    
    case params['type']
    when 'confirmation'
      render plain: confirmation_token
    when 'message_new', 'message_reply'
      Webhooks::VkEventsJob.perform_later(params.to_unsafe_hash)
      render plain: 'ok'
    else
      Rails.logger.warn("Unhandled VK event type: #{params['type']}")
      render plain: 'ok'
    end
  end

  private

  def verify_signature
    return if Rails.env.development?
    
    secret_key = GlobalConfigService.load('VK_SECRET_KEY', '')
    return head :unauthorized if secret_key.blank?
    
    # VK signature verification
    # https://dev.vk.com/api/callback/getting-started#Проверка%20подлинности
    request_body = request.raw_post
    signature = request.headers['X-VK-Signature']
    
    expected_signature = Digest::SHA256.hexdigest(secret_key + request_body)
    
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  def valid_verify_token?
    params['hub.verify_token'] == GlobalConfigService.load('VK_VERIFY_TOKEN', '')
  end

  def confirmation_token
    group_id = params['group_id']
    channel = Channel::Vk.find_by(group_id: group_id)
    channel&.confirmation_token || GlobalConfigService.load('VK_CONFIRMATION_TOKEN', '')
  end
end