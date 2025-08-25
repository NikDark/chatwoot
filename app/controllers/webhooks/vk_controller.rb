class Webhooks::VkController < ActionController::API
  before_action :verify_signature, except: [:verify]

  def verify
    Rails.logger.info("VK webhook verify called with params: #{params.inspect}")
    Rails.logger.info("VK webhook verify headers: #{request.headers.to_h.select { |k,v| k.start_with?('HTTP_') }}")

    # Handle VK callback confirmation
    group_id = params['group_id']
    if group_id.blank?
      Rails.logger.warn("VK webhook verify: missing group_id")
      return head :bad_request
    end

    # Find channel by group_id
    channel = Channel::Vk.find_by(group_id: group_id)
    if channel.blank?
      Rails.logger.warn("VK webhook verify: channel not found for group_id #{group_id}")
      return head :not_found
    end

    begin
      # Get confirmation code from VK API
      confirmation_code = fetch_callback_confirmation_code(channel)
      Rails.logger.info("VK webhook verify: returning confirmation code '#{confirmation_code}' for group #{group_id}")
      render plain: confirmation_code
    rescue StandardError => e
      Rails.logger.error("VK webhook verify error: #{e.message}")
      Rails.logger.error("VK webhook verify backtrace: #{e.backtrace.first(5).join("\n")}")
      head :internal_server_error
    end
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

    if channel.present?
      # Get confirmation code from VK API for the specific channel
      fetch_callback_confirmation_code(channel)
    else
      # Fallback to global confirmation token
      GlobalConfigService.load('VK_CONFIRMATION_TOKEN', '')
    end
  rescue StandardError => e
    Rails.logger.error("VK confirmation token error: #{e.message}")
    # Fallback to global confirmation token on error
    GlobalConfigService.load('VK_CONFIRMATION_TOKEN', '')
  end

  def fetch_callback_confirmation_code(channel)
    response = HTTParty.get(
      'https://api.vk.com/method/groups.getCallbackConfirmationCode',
      query: {
        group_id: channel.group_id,
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    Rails.logger.info("VK афывоалдофыдвоадфоывдлаофываAPI Response: #{response.body}")

    if response.success? && response.parsed_response['response']
      response.parsed_response['response']['code']
    else
      error = response.parsed_response&.dig('error')
      if error
        Rails.logger.error("VK API Error: #{error['error_msg']} (#{error['error_code']})")
        raise "VK API Error: #{error['error_msg']} (#{error['error_code']})"
      else
        raise "VK API request failed: #{response.body}"
      end
    end
  end
end
