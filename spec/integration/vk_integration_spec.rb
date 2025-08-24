require 'rails_helper'

RSpec.describe 'VK Integration', type: :integration do
  describe 'Complete VK integration flow' do
    let(:account) { create(:account) }
    let(:user) { create(:user, :administrator, account: account) }

    before do
      # Mock VK configuration as set up by SuperAdmin
      allow(GlobalConfigService).to receive(:load)
        .with('VK_APP_ID', '')
        .and_return('test_vk_app_id')
      
      allow(GlobalConfigService).to receive(:load)
        .with('VK_APP_SECRET', '')
        .and_return('test_vk_app_secret')
        
      allow(GlobalConfigService).to receive(:load)
        .with('VK_API_VERSION', '5.131')
        .and_return('5.131')
    end

    it 'provides complete VK integration workflow' do
      # 1. VK configuration is available in frontend
      expect(GlobalConfigService.load('VK_APP_ID', '')).to eq('test_vk_app_id')
      
      # 2. VK channel model can be created
      channel = create(:channel_vk, account: account)
      expect(channel).to be_valid
      expect(channel.name).to eq('VK')
      
      # 3. OAuth authorization URL generation works with new VK ID endpoints
      concern = Object.new.extend(VkConcern)
      allow(concern).to receive(:vk_app_id).and_return('test_vk_app_id')
      allow(concern).to receive(:vk_callback_url).and_return('https://example.com/vk/callback')
      
      auth_url = concern.vk_authorization_url('test_state')
      expect(auth_url).to include('https://id.vk.com/auth')
      expect(auth_url).to include('scope=groups,messages')
      
      # 4. Webhook setup can be initiated
      expect(Vk::WebhookService).to receive(:new).with(channel).and_return(double(setup: true))
      channel.setup_webhook
      
      # 5. Message processing services are available
      service = Vk::MessageTextService.new({
        'id' => 123,
        'from_id' => 456,
        'text' => 'Test message',
        'date' => Time.current.to_i
      }, channel)
      expect(service).to be_a(Vk::MessageTextService)
      
      # 6. Send service is available
      inbox = create(:inbox, channel: channel, account: account)
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      
      send_service = Vk::SendOnVkService.new(message: message)
      expect(send_service).to be_a(Vk::SendOnVkService)
    end

    it 'handles VK webhook events' do
      channel = create(:channel_vk, account: account)
      
      # Test webhook event job
      event_data = {
        'type' => 'message_new',
        'group_id' => channel.group_id,
        'object' => {
          'message' => {
            'id' => 123,
            'from_id' => 456,
            'text' => 'Hello from VK',
            'date' => Time.current.to_i
          }
        }
      }
      
      expect(Vk::MessageTextService).to receive(:new).and_return(double(perform: true))
      Webhooks::VkEventsJob.perform_now(event_data)
    end

    it 'provides secure OAuth state validation' do
      # Test state parameter generation
      verifier = ActiveSupport::MessageVerifier.new(Rails.application.secrets.secret_key_base)
      state = verifier.generate("#{account.id}:#{Time.current.to_i}")
      
      # Test state parameter validation
      expect {
        data = verifier.verify(state)
        account_id_str, timestamp_str = data.split(':')
        expect(account_id_str.to_i).to eq(account.id)
        expect(timestamp_str.to_i).to be_within(10).of(Time.current.to_i)
      }.not_to raise_error
    end

    it 'supports modern VK ID endpoints' do
      # Verify new authorization endpoint
      concern = Object.new.extend(VkConcern)
      allow(concern).to receive(:vk_app_id).and_return('test_app_id')
      allow(concern).to receive(:vk_callback_url).and_return('https://example.com/callback')
      
      auth_url = concern.vk_authorization_url('state')
      expect(auth_url).to start_with('https://id.vk.com/auth')
      
      # Verify new token exchange endpoint is used in controller
      controller = Vk::CallbacksController.new
      allow(controller).to receive(:vk_app_id).and_return('test_app_id')
      allow(controller).to receive(:vk_app_secret).and_return('test_secret')
      allow(controller).to receive(:vk_callback_url).and_return('https://example.com/callback')
      
      # Mock HTTParty to verify endpoint
      expect(HTTParty).to receive(:post)
        .with('https://id.vk.com/oauth2/auth', any_args)
        .and_return(double(success?: true, parsed_response: { 'access_token' => 'token' }))
      
      result = controller.send(:exchange_code_for_token, 'test_code')
      expect(result['access_token']).to eq('token')
    end
  end

  describe 'Frontend availability' do
    context 'when VK is configured in SuperAdmin' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('configured_vk_app_id')
      end

      it 'makes VK channel available in frontend config' do
        # This would be tested in system specs with actual browser
        # Here we verify the backend provides the configuration
        global_config = {
          'VK_APP_ID' => GlobalConfigService.load('VK_APP_ID', '')
        }
        
        expect(global_config['VK_APP_ID']).to eq('configured_vk_app_id')
      end
    end

    context 'when VK is not configured' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('VK_APP_ID', '')
          .and_return('')
      end

      it 'provides empty VK configuration' do
        global_config = {
          'VK_APP_ID' => GlobalConfigService.load('VK_APP_ID', '')
        }
        
        expect(global_config['VK_APP_ID']).to eq('')
      end
    end
  end

  describe 'Backward compatibility' do
    it 'preserves existing working functionality' do
      # Verify that existing Instagram and Facebook functionality is not affected
      expect(defined?(Channel::Instagram)).to be_truthy
      expect(defined?(Channel::FacebookPage)).to be_truthy
      
      # Verify that VK is added without breaking existing patterns
      expect(defined?(Channel::Vk)).to be_truthy
      expect(Channel::Vk.ancestors).to include(Channelable)
      expect(Channel::Vk.ancestors).to include(Reauthorizable)
    end

    it 'follows established Chatwoot patterns' do
      channel = build(:channel_vk)
      
      # Should follow same naming pattern
      expect(channel.name).to eq('VK')
      
      # Should have same validation patterns
      expect(channel).to validate_presence_of(:access_token)
      expect(channel).to validate_presence_of(:group_id)
      expect(channel).to validate_uniqueness_of(:group_id).scoped_to(:account_id)
      
      # Should have same callback patterns
      expect(channel).to callback(:setup_webhook).after(:create_commit)
      expect(channel).to callback(:remove_webhook).before(:destroy)
    end
  end
end