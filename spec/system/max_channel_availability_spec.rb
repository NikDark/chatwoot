require 'rails_helper'

RSpec.describe 'MAX Channel Availability', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }

  before do
    sign_in user
  end

  describe 'MAX channel availability in inbox creation' do
    context 'when MAX is not configured in SuperAdmin' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('MAX_APP_ID', '')
          .and_return('')
      end

      it 'MAX channel should not be available for selection' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        max_channel = find('.channel-item', text: 'MAX', visible: false)
        expect(max_channel[:class]).to include('inactive')
      end
    end

    context 'when MAX is properly configured in SuperAdmin' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('MAX_APP_ID', '')
          .and_return('test_max_app_id')
      end

      it 'MAX channel should be available for selection' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        max_channel = find('.channel-item', text: 'MAX')
        expect(max_channel[:class]).not_to include('inactive')
      end

      it 'clicking MAX channel should navigate to MAX setup page' do
        visit "/app/accounts/#{account.id}/settings/inboxes/new"

        click_on 'MAX'

        expect(current_path).to eq("/app/accounts/#{account.id}/settings/inboxes/new/max")
      end
    end
  end

  describe 'configuration validation' do
    it 'validates MAX configuration is passed to frontend' do
      allow(GlobalConfigService).to receive(:load)
        .with('MAX_APP_ID', '')
        .and_return('test_max_app_id_123')

      visit "/app/accounts/#{account.id}/settings/inboxes/new"

      max_app_id = page.evaluate_script('window.chatwootConfig.maxAppId')
      expect(max_app_id).to eq('test_max_app_id_123')
    end

    it 'handles empty MAX configuration gracefully' do
      allow(GlobalConfigService).to receive(:load)
        .with('MAX_APP_ID', '')
        .and_return('')

      visit "/app/accounts/#{account.id}/settings/inboxes/new"

      max_app_id = page.evaluate_script('window.chatwootConfig.maxAppId')
      expect(max_app_id).to eq('')
    end
  end
end

