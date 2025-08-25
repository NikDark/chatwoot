class Api::V1::Accounts::Vk::AuthorizationsController < Api::V1::Accounts::BaseController
  include VkConcern
  include Vk::IntegrationHelper

  def create
    # Generate authorization URL with simple state and code_challeknge
    authorization_url = vk_authorization_url(Current.account.id)

    render json: {
      url: authorization_url
    }
  end
end
