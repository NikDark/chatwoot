require 'rails_helper'

RSpec.describe 'layouts/vueapp.html.erb', type: :view do
  let(:global_config) do
    {
      'FB_APP_ID' => 'facebook_app_id_123',
      'INSTAGRAM_APP_ID' => 'instagram_app_id_456',
      'VK_APP_ID' => 'vk_app_id_789',
      'FACEBOOK_API_VERSION' => 'v17.0',
      'WHATSAPP_APP_ID' => 'whatsapp_app_id',
      'WHATSAPP_CONFIGURATION_ID' => 'whatsapp_config_id'
    }
  end

  before do
    assign(:global_config, global_config)
    allow(ENV).to receive(:fetch).with('FRONTEND_URL', '').and_return('https://example.com')
    allow(ENV).to receive(:fetch).with('HELPCENTER_URL', '').and_return('https://help.example.com')
    allow(ENV).to receive(:fetch).with('GOOGLE_OAUTH_CLIENT_ID', nil).and_return('google_client_id')
    allow(ENV).to receive(:fetch).with('GOOGLE_OAUTH_CALLBACK_URL', nil).and_return('https://example.com/oauth/callback')
  end

  describe 'chatwootConfig JavaScript object' do
    it 'includes VK app ID in configuration' do
      render

      expect(rendered).to include("vkAppId: 'vk_app_id_789'")
    end

    it 'includes Facebook app ID in configuration' do
      render

      expect(rendered).to include("fbAppId: 'facebook_app_id_123'")
    end

    it 'includes Instagram app ID in configuration' do
      render

      expect(rendered).to include("instagramAppId: 'instagram_app_id_456'")
    end

    it 'includes all required configuration keys' do
      render

      expect(rendered).to include("window.chatwootConfig = {")
      expect(rendered).to include("hostURL: 'https://example.com'")
      expect(rendered).to include("helpCenterURL: 'https://help.example.com'")
      expect(rendered).to include("fbAppId: 'facebook_app_id_123'")
      expect(rendered).to include("instagramAppId: 'instagram_app_id_456'")
      expect(rendered).to include("vkAppId: 'vk_app_id_789'")
      expect(rendered).to include("googleOAuthClientId: 'google_client_id'")
    end

    context 'when VK app ID is not configured' do
      before do
        global_config['VK_APP_ID'] = nil
      end

      it 'includes empty VK app ID' do
        render

        expect(rendered).to include("vkAppId: ''")
      end
    end

    context 'when VK app ID is empty string' do
      before do
        global_config['VK_APP_ID'] = ''
      end

      it 'includes empty VK app ID' do
        render

        expect(rendered).to include("vkAppId: ''")
      end
    end
  end
end