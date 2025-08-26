require 'rails_helper'

RSpec.describe 'VK Channel Availability', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }

  before do
    sign_in user
  end

  describe 'VK channel availability in inbox creation' do
    context 'when VK is not configured in SuperAdmin' do
      before do
        # Ensure VK_APP_ID is not set
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('')
      end

      it 'VK channel should not be available for selection' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        # The VK channel should not be clickable/active
        vk_channel = find('.channel-item', text: 'VK', visible: false)
        expect(vk_channel[:class]).to include('inactive')
      end
    end

    context 'when VK is properly configured in SuperAdmin' do
      before do
        # Mock VK_APP_ID as configured
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('test_vk_app_id')
        
        # Mock other required configs
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_SECRET', '')
          .and_return('test_vk_app_secret')
          
        allow(GlobalConfigService).to receive(:load)
          .with('VK_API_VERSION', '5.131')
          .and_return('5.131')
      end

      it 'VK channel should be available for selection' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        # The VK channel should be clickable/active
        vk_channel = find('.channel-item', text: 'VK')
        expect(vk_channel[:class]).not_to include('inactive')
      end

      it 'clicking VK channel should navigate to VK setup page' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        # Click on VK channel
        click_on 'VK'

        # Should navigate to VK channel setup
        expect(current_path).to eq("/app/accounts/#{account.id}/settings/inboxes/new/vk")
      end
    end
  end

  describe 'configuration validation' do
    it 'validates VK configuration is passed to frontend' do
      # Set up VK configuration
      allow(GlobalConfigService).to receive(:load)
        .with('VK_APP_ID', '')
        .and_return('test_vk_app_id_123')

      visit "/app/accounts/#{account.id}/settings/inboxes/new"

      # Check that VK app ID is available in JavaScript
      vk_app_id = page.evaluate_script('window.chatwootConfig.vkAppId')
      expect(vk_app_id).to eq('test_vk_app_id_123')
    end

    it 'handles empty VK configuration gracefully' do
      allow(GlobalConfigService).to receive(:load)
        .with('VK_APP_ID', '')
        .and_return('')

      visit "/app/accounts/#{account.id}/settings/inboxes/new"

      # Check that empty VK app ID is handled
      vk_app_id = page.evaluate_script('window.chatwootConfig.vkAppId')
      expect(vk_app_id).to eq('')
    end
  end

  describe 'comparison with other social channels' do
    context 'when Facebook is configured but VK is not' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('FB_APP_ID', '')
          .and_return('facebook_app_id')
          
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('')
      end

      it 'Facebook should be available but VK should not' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        facebook_channel = find('.channel-item', text: 'Messenger')
        vk_channel = find('.channel-item', text: 'VK', visible: false)

        expect(facebook_channel[:class]).not_to include('inactive')
        expect(vk_channel[:class]).to include('inactive')
      end
    end

    context 'when Instagram is configured but VK is not' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('INSTAGRAM_APP_ID', '')
          .and_return('instagram_app_id')
          
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('')
      end

      it 'Instagram should be available but VK should not' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        instagram_channel = find('.channel-item', text: 'Instagram')
        vk_channel = find('.channel-item', text: 'VK', visible: false)

        expect(instagram_channel[:class]).not_to include('inactive')
        expect(vk_channel[:class]).to include('inactive')
      end
    end

    context 'when all social channels are configured' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('FB_APP_ID', '')
          .and_return('facebook_app_id')
          
        allow(GlobalConfigService).to receive(:load)
          .with('INSTAGRAM_APP_ID', '')
          .and_return('instagram_app_id')
          
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('vk_app_id')
      end

      it 'all social channels should be available' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        facebook_channel = find('.channel-item', text: 'Messenger')
        instagram_channel = find('.channel-item', text: 'Instagram')
        vk_channel = find('.channel-item', text: 'VK')

        expect(facebook_channel[:class]).not_to include('inactive')
        expect(instagram_channel[:class]).not_to include('inactive')
        expect(vk_channel[:class]).not_to include('inactive')
      end
    end
  end
end