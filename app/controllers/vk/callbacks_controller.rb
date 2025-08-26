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

    account_id = state

    @account = Account.find(account_id)

    # First step: get user access token
    token_response = exchange_code_for_token(code)

    # Get user's admin groups
    admin_groups = fetch_user_admin_groups(token_response['access_token'])

    if admin_groups.empty?
      redirect_to app_new_vk_inbox_url(
        account_id: @account.id,
        error_message: 'No VK groups found where you are an administrator. You need to be an admin of at least one VK group to connect it to Chatwoot.'
      )
      return
    end

    # Generate state for groups authorization
    pkce_params = generate_pkce_parameters
    groups_state = @account.id
    group_ids = admin_groups.map { |group| group['id'] }

    # Generate groups authorization URL
    groups_auth_url = vk_groups_authorization_url(groups_state, group_ids)

    # Redirect to groups authorization (external VK domain)
    redirect_to groups_auth_url, allow_other_host: true
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

  def fetch_user_admin_groups(access_token)
    response = HTTParty.get(
      'https://api.vk.com/method/groups.get',
      query: {
        access_token: access_token,
        filter: 'admin',
        extended: 1,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )

    if response.success? && response.parsed_response['response']
      response.parsed_response['response']['items'] || []
    else
      raise "Failed to fetch admin groups: #{response.body}"
    end
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
        account_id
      end
    rescue StandardError => e
      Rails.logger.debug("VK: Failed to extract account_id from Redis for error context: #{e.message}")
      nil
    end
  end
end
