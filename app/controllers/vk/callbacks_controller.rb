class Vk::CallbacksController < ApplicationController
  include VkConcern

  def show
    return handle_error if params[:error].present?
    
    process_authorization
  rescue StandardError => e
    handle_error(e)
  end

  private

  def process_authorization
    code = params[:code]
    
    token_response = exchange_code_for_token(code)
    group_info = fetch_group_info(token_response['access_token'])
    
    channel = find_or_create_channel(token_response, group_info)
    create_or_update_inbox(channel, group_info)
    
    redirect_to app_vk_inbox_agents_url(
      account_id: current_user.account_id,
      inbox_id: channel.inbox.id
    )
  end

  def exchange_code_for_token(code)
    response = HTTParty.post(
      'https://oauth.vk.com/access_token',
      body: {
        client_id: vk_app_id,
        client_secret: vk_app_secret,
        redirect_uri: vk_callback_url,
        code: code
      }
    )
    
    if response.success?
      response.parsed_response
    else
      raise "Token exchange failed: #{response.body}"
    end
  end

  def fetch_group_info(access_token)
    response = HTTParty.get(
      'https://api.vk.com/method/groups.getById',
      query: {
        access_token: access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    if response.success? && response.parsed_response['response']
      response.parsed_response['response'].first
    else
      raise "Failed to fetch group info: #{response.body}"
    end
  end

  def find_or_create_channel(token_response, group_info)
    existing_channel = Channel::Vk.find_by(
      group_id: group_info['id'].to_s,
      account: current_user.account
    )
    
    if existing_channel
      existing_channel.update!(
        access_token: token_response['access_token'],
        group_name: group_info['name']
      )
      existing_channel
    else
      Channel::Vk.create!(
        account: current_user.account,
        access_token: token_response['access_token'],
        group_id: group_info['id'].to_s,
        group_name: group_info['name'],
        confirmation_token: SecureRandom.hex(16)
      )
    end
  end

  def create_or_update_inbox(channel, group_info)
    return if channel.inbox.present?
    
    current_user.account.inboxes.create!(
      account: current_user.account,
      channel: channel,
      name: group_info['name']
    )
  end

  def handle_error(error = nil)
    error_message = error&.message || params[:error_description] || 'Authorization failed'
    
    Rails.logger.error("VK authorization error: #{error_message}")
    
    redirect_to app_new_vk_inbox_url(
      account_id: current_user.account_id,
      error_message: error_message
    )
  end
end