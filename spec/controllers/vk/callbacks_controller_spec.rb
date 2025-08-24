require 'rails_helper'

RSpec.describe Vk::CallbacksController, type: :controller do
  let(:user) { create(:user) }
  let(:account) { user.account }
  
  before do
    sign_in user
  end

  describe 'GET #show' do
    context 'with successful authorization' do
      let(:valid_code) { 'valid_authorization_code' }
      let(:access_token) { 'vk_access_token' }
      let(:group_info) do
        {
          'id' => 123456,
          'name' => 'Test VK Community'
        }
      end
      
      before do
        # Mock VK OAuth token exchange
        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(
            success?: true,
            parsed_response: { 'access_token' => access_token }
          ))
          
        # Mock VK group info fetch
        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/groups.getById', any_args)
          .and_return(double(
            success?: true,
            parsed_response: { 'response' => [group_info] }
          ))
      end

      it 'creates VK channel and inbox' do
        expect {
          get :show, params: { code: valid_code }
        }.to change(Channel::Vk, :count).by(1)
          .and change(Inbox, :count).by(1)
        
        channel = Channel::Vk.last
        expect(channel.access_token).to eq(access_token)
        expect(channel.group_id).to eq('123456')
        expect(channel.group_name).to eq('Test VK Community')
        expect(channel.account).to eq(account)
        
        inbox = channel.inbox
        expect(inbox.name).to eq('Test VK Community')
        expect(inbox.account).to eq(account)
      end

      it 'updates existing channel if group already exists' do
        existing_channel = create(:channel_vk, 
          account: account, 
          group_id: '123456',
          access_token: 'old_token',
          group_name: 'Old Name'
        )
        
        expect {
          get :show, params: { code: valid_code }
        }.not_to change(Channel::Vk, :count)
        
        existing_channel.reload
        expect(existing_channel.access_token).to eq(access_token)
        expect(existing_channel.group_name).to eq('Test VK Community')
      end

      it 'redirects to inbox agents page' do
        get :show, params: { code: valid_code }
        
        channel = Channel::Vk.last
        expect(response).to redirect_to(
          app_vk_inbox_agents_url(
            account_id: account.id,
            inbox_id: channel.inbox.id
          )
        )
      end
    end

    context 'with authorization error' do
      it 'handles error parameter' do
        get :show, params: { 
          error: 'access_denied',
          error_description: 'User denied access'
        }
        
        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            error_message: 'User denied access'
          )
        )
      end
    end

    context 'with token exchange failure' do
      before do
        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(success?: false, body: 'Token exchange failed'))
      end

      it 'handles token exchange error' do
        get :show, params: { code: 'invalid_code' }
        
        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            error_message: 'Token exchange failed: Token exchange failed'
          )
        )
      end
    end

    context 'with group info fetch failure' do
      before do
        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(
            success?: true,
            parsed_response: { 'access_token' => 'token' }
          ))
          
        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/groups.getById', any_args)
          .and_return(double(success?: false, body: 'Group fetch failed'))
      end

      it 'handles group info fetch error' do
        get :show, params: { code: 'valid_code' }
        
        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            error_message: 'Failed to fetch group info: Group fetch failed'
          )
        )
      end
    end
  end
end