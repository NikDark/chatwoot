require 'rails_helper'

RSpec.describe Vk::GroupsCallbacksController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    sign_in user
  end

  describe 'GET #show' do
    context 'with successful groups authorization' do
      let(:valid_code) { 'valid_groups_authorization_code' }
      let(:state) { 'valid_state_from_redis' }
      let(:oauth_data) { { account_id: account.id } }
      let(:groups_response) do
        {
          'groups' => [
            {
              'group_id' => '123456',
              'access_token' => 'group_access_token_123'
            }
          ]
        }
      end
      let(:group_info) do
        {
          'id' => 123456,
          'name' => 'Test VK Group'
        }
      end

      before do
        # Mock VK integration helper methods
        allow(controller).to receive(:retrieve_vk_oauth_data)
          .with(state)
          .and_return(oauth_data)

        # Mock VK API calls
        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(
            success?: true,
            parsed_response: groups_response
          ))

        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/groups.getById', any_args)
          .and_return(double(
            success?: true,
            parsed_response: { 'response' => [group_info] }
          ))
      end

      it 'creates VK channel and inbox' do
        expect {
          get :show, params: { code: valid_code, state: state }
        }.to change(Channel::Vk, :count).by(1)
          .and change(Inbox, :count).by(1)

        channel = Channel::Vk.last
        expect(channel.access_token).to eq('group_access_token_123')
        expect(channel.group_id).to eq('123456')
        expect(channel.group_name).to eq('Test VK Group')
        expect(channel.account).to eq(account)

        inbox = channel.inbox
        expect(inbox.name).to eq('Test VK Group')
        expect(inbox.account).to eq(account)
      end

      it 'redirects to inbox finish page, skipping agent selection' do
        get :show, params: { code: valid_code, state: state }

        channel = Channel::Vk.last
        expect(response).to redirect_to(
          app_inbox_finish_url(
            account_id: account.id,
            inbox_id: channel.inbox.id
          )
        )
      end

      it 'updates existing channel if group already exists' do
        existing_channel = create(:channel_vk,
          account: account,
          group_id: '123456',
          access_token: 'old_token',
          group_name: 'Old Name'
        )

        expect {
          get :show, params: { code: valid_code, state: state }
        }.not_to change(Channel::Vk, :count)

        existing_channel.reload
        expect(existing_channel.access_token).to eq('group_access_token_123')
        expect(existing_channel.group_name).to eq('Test VK Group')
      end
    end

    context 'with authorization error' do
      it 'handles error parameter' do
        get :show, params: {
          error: 'access_denied',
          error_description: 'User denied access to groups'
        }

        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            error_message: 'User denied access to groups'
          )
        )
      end
    end

    context 'with invalid state parameter' do
      it 'handles invalid state from Redis' do
        allow(controller).to receive(:retrieve_vk_oauth_data)
          .with('invalid_state')
          .and_return(nil)

        get :show, params: { code: 'valid_code', state: 'invalid_state' }

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('VK groups authorization failed')
      end
    end

    context 'with groups token exchange failure' do
      let(:state) { 'valid_state' }
      let(:oauth_data) { { account_id: account.id } }

      before do
        allow(controller).to receive(:retrieve_vk_oauth_data)
          .with(state)
          .and_return(oauth_data)

        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(success?: false, body: 'Token exchange failed'))
      end

      it 'handles token exchange error' do
        get :show, params: { code: 'invalid_code', state: state }

        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            error_message: 'Failed to get access tokens for VK groups. Please try again.'
          )
        )
      end
    end

    context 'with group info fetch failure' do
      let(:state) { 'valid_state' }
      let(:oauth_data) { { account_id: account.id } }
      let(:groups_response) do
        {
          'groups' => [
            {
              'group_id' => '123456',
              'access_token' => 'group_access_token_123'
            }
          ]
        }
      end

      before do
        allow(controller).to receive(:retrieve_vk_oauth_data)
          .with(state)
          .and_return(oauth_data)

        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(
            success?: true,
            parsed_response: groups_response
          ))

        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/groups.getById', any_args)
          .and_return(double(success?: false, body: 'Group fetch failed'))
      end

      it 'handles group info fetch error' do
        get :show, params: { code: 'valid_code', state: state }

        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            error_message: 'Failed to fetch group info for group 123456: Group fetch failed'
          )
        )
      end
    end

    context 'with no groups created' do
      let(:state) { 'valid_state' }
      let(:oauth_data) { { account_id: account.id } }
      let(:groups_response) { { 'groups' => [] } }

      before do
        allow(controller).to receive(:retrieve_vk_oauth_data)
          .with(state)
          .and_return(oauth_data)

        allow(HTTParty).to receive(:post)
          .with('https://oauth.vk.com/access_token', any_args)
          .and_return(double(
            success?: true,
            parsed_response: groups_response
          ))
      end

      it 'redirects with success message when no groups are created' do
        get :show, params: { code: 'valid_code', state: state }

        expect(response).to redirect_to(
          app_new_vk_inbox_url(
            account_id: account.id,
            success_message: 'VK groups connected successfully, but no new channels were created.'
          )
        )
      end
    end
  end
end