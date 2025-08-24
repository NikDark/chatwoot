class Api::V1::Accounts::Vk::AuthorizationsController < Api::V1::Accounts::BaseController
  include VkConcern

  def create
    state = encode_state(current_user.account_id)
    authorization_url = vk_authorization_url(state)
    
    render json: {
      url: authorization_url
    }
  end

  private

  def encode_state(account_id)
    # Create secure state parameter with timestamp and account ID
    # Include timestamp to prevent replay attacks
    timestamp = Time.current.to_i
    data = "#{account_id}:#{timestamp}"
    
    # Sign the data with Rails secret to prevent tampering
    verifier = ActiveSupport::MessageVerifier.new(Rails.application.secrets.secret_key_base)
    verifier.generate(data)
  end
end