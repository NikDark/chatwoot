require 'rails_helper'

RSpec.describe Vk::WebhookService do
  let(:channel) { create(:channel_vk) }
  let(:service) { described_class.new(channel) }
  let(:webhook_url) { 'https://example.com/webhooks/vk' }
  let(:secret_key) { 'test_secret_key' }

  before do
    allow(GlobalConfigService).to receive(:load)
      .with('VK_WEBHOOK_SECRET', '')
      .and_return(secret_key)
      
    allow(Rails.application.routes.url_helpers).to receive(:webhooks_vk_url)
      .and_return(webhook_url)
  end

  describe '#setup' do
    let(:server_response) do
      double(
        success?: true,
        parsed_response: { 'response' => { 'server_id' => 12345 } }
      )
    end

    let(:settings_response) do
      double(
        success?: true,
        parsed_response: { 'response' => {} }
      )
    end

    before do
      allow(HTTParty).to receive(:get)
        .with('https://api.vk.com/method/groups.addCallbackServer', any_args)
        .and_return(server_response)
        
      allow(HTTParty).to receive(:get)
        .with('https://api.vk.com/method/groups.setCallbackSettings', any_args)
        .and_return(settings_response)
    end

    it 'adds callback server' do
      expect(HTTParty).to receive(:get)
        .with(
          'https://api.vk.com/method/groups.addCallbackServer',
          query: {
            group_id: channel.group_id,
            url: webhook_url,
            title: 'Chatwoot Integration',
            secret_key: secret_key,
            access_token: channel.access_token,
            v: '5.131'
          }
        )
        .and_return(server_response)

      service.setup
    end

    it 'configures callback settings' do
      expect(HTTParty).to receive(:get)
        .with(
          'https://api.vk.com/method/groups.setCallbackSettings',
          query: {
            group_id: channel.group_id,
            server_id: 12345,
            message_new: 1,
            message_reply: 1,
            access_token: channel.access_token,
            v: '5.131'
          }
        )
        .and_return(settings_response)

      service.setup
    end

    it 'logs success message' do
      expect(Rails.logger).to receive(:info)
        .with("VK webhook configured for group #{channel.group_id}")

      service.setup
    end
  end

  describe '#remove' do
    let(:servers_list) do
      [
        { 'id' => 1, 'url' => 'https://other.com/webhook' },
        { 'id' => 2, 'url' => webhook_url },
        { 'id' => 3, 'url' => 'https://another.com/webhook' }
      ]
    end

    let(:get_servers_response) do
      double(
        success?: true,
        parsed_response: { 'response' => { 'items' => servers_list } }
      )
    end

    let(:delete_response) do
      double(
        success?: true,
        parsed_response: { 'response' => {} }
      )
    end

    before do
      allow(HTTParty).to receive(:get)
        .with('https://api.vk.com/method/groups.getCallbackServers', any_args)
        .and_return(get_servers_response)
        
      allow(HTTParty).to receive(:get)
        .with('https://api.vk.com/method/groups.deleteCallbackServer', any_args)
        .and_return(delete_response)
    end

    it 'gets callback servers' do
      expect(HTTParty).to receive(:get)
        .with(
          'https://api.vk.com/method/groups.getCallbackServers',
          query: {
            group_id: channel.group_id,
            access_token: channel.access_token,
            v: '5.131'
          }
        )
        .and_return(get_servers_response)

      service.remove
    end

    it 'removes matching webhook server' do
      expect(HTTParty).to receive(:get)
        .with(
          'https://api.vk.com/method/groups.deleteCallbackServer',
          query: {
            group_id: channel.group_id,
            server_id: 2,
            access_token: channel.access_token,
            v: '5.131'
          }
        )
        .and_return(delete_response)

      service.remove
    end

    it 'does not remove non-matching servers' do
      expect(HTTParty).not_to receive(:get)
        .with(
          'https://api.vk.com/method/groups.deleteCallbackServer',
          query: hash_including(server_id: 1)
        )

      expect(HTTParty).not_to receive(:get)
        .with(
          'https://api.vk.com/method/groups.deleteCallbackServer',
          query: hash_including(server_id: 3)
        )

      service.remove
    end

    it 'logs success message' do
      expect(Rails.logger).to receive(:info)
        .with("VK webhook removed for group #{channel.group_id}")

      service.remove
    end
  end

  describe 'API error handling' do
    let(:error_response) do
      double(
        success?: true,
        parsed_response: {
          'error' => {
            'error_code' => 5,
            'error_msg' => 'User authorization failed'
          }
        }
      )
    end

    before do
      allow(HTTParty).to receive(:get)
        .with('https://api.vk.com/method/groups.addCallbackServer', any_args)
        .and_return(error_response)
    end

    it 'raises error with VK API error message' do
      expect {
        service.setup
      }.to raise_error('VK API Error: User authorization failed (5)')
    end

    it 'handles authorization error in channel' do
      expect(channel).to receive(:authorization_error!)
      
      begin
        service.setup
      rescue StandardError
        # Expected error
      end
    end
  end
end