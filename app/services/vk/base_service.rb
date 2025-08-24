class Vk::BaseService
  attr_reader :channel

  def initialize(channel)
    @channel = channel
    @inbox = channel.inbox
  end

  private

  def api_request(method, params = {})
    response = HTTParty.get(
      "https://api.vk.com/method/#{method}",
      query: params.merge(
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      )
    )
    
    if response.success? && response.parsed_response['response']
      response.parsed_response['response']
    else
      error = response.parsed_response&.dig('error')
      if error
        handle_api_error(error)
        raise "VK API Error: #{error['error_msg']} (#{error['error_code']})"
      else
        raise "VK API request failed: #{response.body}"
      end
    end
  end

  def handle_api_error(error)
    error_code = error['error_code']
    
    case error_code
    when 5 # User authorization failed
      channel.authorization_error!
    when 7 # Permission to perform this action is denied
      Rails.logger.error("VK permission denied: #{error['error_msg']}")
    when 901 # Can't send messages for users without permission
      Rails.logger.warn("VK user blocked messages: #{error['error_msg']}")
    end
    
    Rails.logger.error("VK API Error: #{error['error_msg']} (Code: #{error_code})")
  end
end