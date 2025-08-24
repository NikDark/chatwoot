require 'rails_helper'

RSpec.describe Api::V1::Accounts::Vk::AuthorizationsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    sign_in user
  end

  describe 'POST #create' do
    before do
      allow(GlobalConfigService).to receive(:load)
        .with('VK_APP_ID', '')
        .and_return('test_app_id')
        
      allow(GlobalConfigService).to receive(:load)
        .with('VK_API_VERSION', '5.131')
        .and_return('5.131')
        
      allow(Rails.application.routes.url_helpers).to receive(:vk_callback_url)
        .and_return('https://example.com/vk/callback')
    end

    it 'returns VK authorization URL' do
      post :create

      expect(response).to have_http_status(:ok)
      
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('url')
      
      url = json_response['url']
      expect(url).to include('https://oauth.vk.com/authorize')
      expect(url).to include('client_id=test_app_id')
      expect(url).to include('scope=messages,groups')
      expect(url).to include('response_type=code')
      expect(url).to include('v=5.131')
      expect(url).to include('redirect_uri=https://example.com/vk/callback')
      expect(url).to include('state=')
    end

    it 'includes encoded account ID in state parameter' do
      post :create

      json_response = JSON.parse(response.body)
      url = URI.parse(json_response['url'])
      params = CGI.parse(url.query)
      
      state = params['state'].first
      decoded_account_id = Base64.urlsafe_decode64(state)
      
      expect(decoded_account_id).to eq(account.id.to_s)
    end
  end
end