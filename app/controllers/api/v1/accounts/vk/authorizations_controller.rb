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
    # Simple state encoding to verify the callback
    # In production, consider using JWT or similar for better security
    Base64.urlsafe_encode64(account_id.to_s)
  end
end