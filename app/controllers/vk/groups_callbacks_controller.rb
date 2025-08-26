class Vk::GroupsCallbacksController < ApplicationController
  include VkConcern
  include Vk::IntegrationHelper

  def show
    return handle_error if params[:error].present?

    process_groups_authorization
  rescue StandardError => e
    handle_error(e)
  end

  private

  def process_groups_authorization
    code = params[:code]
    state = params[:state]


    account_id = state
    @account = Account.find(account_id)

    # Exchange code for group tokens
    groups_response = exchange_code_for_group_tokens(code)

    # Create channels for each group
    created_channels = []
    groups_response['groups'].each do |group_data|
      group_info = fetch_single_group_info(group_data['access_token'], group_data['group_id'])
      channel = find_or_create_channel(group_data, group_info)
      inbox_created_or_updated = create_or_update_inbox(channel, group_info)
      created_channels << channel if inbox_created_or_updated
    end

    # Redirect directly to success page, skipping agent selection
    if created_channels.any?
      redirect_to app_inbox_finish_url(
        account_id: @account.id,
        inbox_id: created_channels.first.inbox.id
      )
    else
      redirect_to app_new_vk_inbox_url(
        account_id: @account.id,
        success_message: 'VK groups connected successfully, but no new inboxes were created.'
      )
    end
  end

  def exchange_code_for_group_tokens(code)
    request_body = {
      code: code,
      redirect_uri: vk_groups_callback_url,
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
      raise "Group tokens exchange failed: #{response.body}"
    end
  end

  def fetch_single_group_info(access_token, group_id)
    response = HTTParty.get(
      'https://api.vk.com/method/groups.getById',
      query: {
        group_id: group_id,
        access_token: access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )

    if response.success? && response.parsed_response['response']
      response.parsed_response['response'].first
    else
      raise "Failed to fetch group info for group #{group_id}: #{response.body}"
    end
  end

  def find_or_create_channel(group_data, group_info)
    existing_channel = Channel::Vk.find_by(
      group_id: group_data['group_id'],
      account: @account
    )

    if existing_channel
      existing_channel.update!(
        access_token: group_data['access_token'],
        group_name: group_info['name']
      )
      existing_channel
    else
      channel = Channel::Vk.create!(
        account: @account,
        access_token: group_data['access_token'],
        group_id: group_data['group_id'],
        group_name: group_info['name'],
        confirmation_token: SecureRandom.hex(16)
      )
      channel
    end
  end

  def create_or_update_inbox(channel, group_info)
    if channel.inbox.present?
      # Update existing inbox name if it has changed
      if channel.inbox.name != group_info['name']
        channel.inbox.update!(name: group_info['name'])
        Rails.logger.info("VK Groups Callback: Updated inbox name for group #{group_info['name']}")
      else
        Rails.logger.info("VK Groups Callback: Inbox already exists for group #{group_info['name']}")
      end
      return false
    end

    inbox = @account.inboxes.create!(
      account: @account,
      channel: channel,
      name: group_info['name']
    )

    # Force reload the channel to ensure the association is loaded
    channel.reload

    true
  end

  def handle_error(error = nil)
    error_message = error&.message || params[:error_description] || 'VK groups authorization failed'

    # Provide more user-friendly error messages
    user_friendly_message = case error_message
                           when /Invalid or expired VK authorization state/i
                             'VK groups authorization session has expired. Please try connecting VK groups again.'
                           when /Group tokens exchange failed/i
                             'Failed to get access tokens for VK groups. Please try again.'
                           else
                             error_message
                           end

    Rails.logger.error("VK groups authorization error: #{error_message}")

    # Try to get account_id from JWT state parameter
    account_id = get_account_id_from_error_context

    if account_id.present?
      redirect_to app_new_vk_inbox_url(
        account_id: account_id,
        error_message: user_friendly_message
      )
    else
      # Fallback: redirect to root with error message
      redirect_to root_path, alert: "VK groups authorization failed: #{user_friendly_message}"
    end
  end

  def get_account_id_from_error_context
    # First try to use account from validated state
    return @account&.id if @account.present?

    # Try to extract account_id from Redis state parameter
    state = params[:state]
    return nil if state.blank?

    # Try to retrieve OAuth data for error context (without deleting from Redis)
    begin
      data = peek_vk_oauth_data(state)
      if data.present?
        account_id = data[:account_id]
        Rails.logger.info("VK Groups: Extracted account_id #{account_id} from Redis for error context")
        account_id
      end
    rescue StandardError => e
      Rails.logger.debug("VK Groups: Failed to extract account_id from Redis for error context: #{e.message}")
      nil
    end
  end


end
