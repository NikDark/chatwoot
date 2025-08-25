class Vk::CallbacksController < ApplicationController
  include VkConcern
  include Vk::IntegrationHelper

  def show
    return handle_error if params[:error].present?

    process_authorization
  rescue StandardError => e
    handle_error(e)
  end

  private

  def process_authorization
    code = params[:code]
    state = params[:state]

    Rails.logger.info("VK Callback: Code: #{code}")
    Rails.logger.info("VK Callback: State: #{state}")

    account_id = state

    @account = Account.find(account_id)
    Rails.logger.info("VK Callback: Found account: #{@account.name}")

    token_response = exchange_code_for_token(code)
    Rails.logger.info("VK Callback: Token response: #{token_response}")
    group_info = fetch_group_info(token_response['access_token'])
    Rails.logger.info(group_info)

    channel = find_or_create_channel(token_response, group_info)
    create_or_update_inbox(channel, group_info)

    redirect_to app_vk_inbox_agents_url(
      account_id: account.id,
      inbox_id: channel.inbox.id
    )
  end

  def exchange_code_for_token(code)
    request_body = {
      code: code,
      redirect_uri: vk_callback_url,
      client_id: vk_app_id,
      client_secret: vk_app_secret,
    }

    response = HTTParty.post(
      'https://oauth.vk.com/access_token',
      body: request_body
    )

    if response.success?
      response.parsed_response
    else
      raise "Token exchange failed: #{response.body}"
    end
  end

  def fetch_group_info(access_token)
    response = HTTParty.get(
      'https://api.vk.com/method/groups.get',
      query: {
        access_token: access_token,
        filter: ['admin'],
        extended: 1,
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
      group_id: group_info['id'],
      account: account
    )

    if existing_channel
      existing_channel.update!(
        access_token: token_response['access_token'],
        group_name: group_info['name']
      )
      existing_channel
    else
      Channel::Vk.create!(
        account: account,
        access_token: token_response['access_token'],
        group_id: group_info['id'],
        group_name: group_info['name'],
        confirmation_token: SecureRandom.hex(16)
      )
    end
  end

  def create_or_update_inbox(channel, group_info)
    return if channel.inbox.present?

    account.inboxes.create!(
      account: account,
      channel: channel,
      name: group_info['name']
    )
  end



  def account
    @account
  end

  def handle_error(error = nil)
    error_message = error&.message || params[:error_description] || 'Authorization failed'

    # Provide more user-friendly error messages
    user_friendly_message = case error_message
                           when /Invalid or expired VK authorization state/i
                             'VK authorization session has expired. Please try connecting VK again.'
                           when /Missing.*in VK OAuth data/i
                             'VK authorization session is corrupted. Please try connecting VK again.'
                           else
                             error_message
                           end

    Rails.logger.error("VK authorization error: #{error_message}")

    # Try to get account_id from JWT state parameter
    account_id = get_account_id_from_error_context

    if account_id.present?
      redirect_to app_new_vk_inbox_url(
        account_id: account_id,
        error_message: user_friendly_message
      )
    else
      # Fallback: redirect to root with error message
      redirect_to root_path, alert: "VK authorization failed: #{user_friendly_message}"
    end
  end

  def get_account_id_from_error_context
    # First try to use account from validated state
    return account&.id if account.present?

    # Try to extract account_id from Redis state parameter
    state = params[:state]
    return nil if state.blank?

    # Try to retrieve OAuth data for error context (without deleting from Redis)
    begin
      data = peek_vk_oauth_data(state)
      if data.present?
        account_id = data[:account_id]
        Rails.logger.info("VK: Extracted account_id #{account_id} from Redis for error context")
        account_id
      end
    rescue StandardError => e
      Rails.logger.debug("VK: Failed to extract account_id from Redis for error context: #{e.message}")
      nil
    end
  end
end
