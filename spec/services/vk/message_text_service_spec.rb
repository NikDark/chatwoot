require 'rails_helper'

RSpec.describe Vk::MessageTextService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_vk, account: account) }
  let(:inbox) { create(:inbox, channel: channel, account: account) }
  let(:message_data) do
    {
      'id' => 123,
      'from_id' => 456,
      'text' => 'Hello from VK user',
      'date' => Time.current.to_i
    }
  end
  let(:service) { described_class.new(message_data, channel) }

  before do
    allow(channel).to receive(:inbox).and_return(inbox)
  end

  describe '#perform' do
    context 'with valid message' do
      let(:user_info) do
        {
          'first_name' => 'John',
          'last_name' => 'Doe',
          'photo_200' => 'https://example.com/photo.jpg'
        }
      end

      before do
        # Mock VK API user info fetch
        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/users.get', any_args)
          .and_return(double(
            success?: true,
            parsed_response: { 'response' => [user_info] }
          ))
      end

      it 'creates contact inbox and processes message' do
        expect(ContactInboxWithContactBuilder).to receive(:new)
          .with({
            source_id: '456',
            inbox: inbox,
            contact_attributes: { name: 'John Doe' }
          })
          .and_return(double(perform: create(:contact_inbox, inbox: inbox, source_id: '456')))

        expect(Messages::Vk::MessageBuilder).to receive(:new)
          .with(message_data, inbox, instance_of(ContactInbox))
          .and_return(double(perform: true))

        service.perform
      end

      it 'reuses existing contact inbox' do
        contact_inbox = create(:contact_inbox, inbox: inbox, source_id: '456')

        expect(ContactInboxWithContactBuilder).not_to receive(:new)
        expect(Messages::Vk::MessageBuilder).to receive(:new)
          .with(message_data, inbox, contact_inbox)
          .and_return(double(perform: true))

        service.perform
      end
    end

    context 'with invalid message' do
      it 'skips message without text' do
        message_data['text'] = ''
        
        expect(ContactInboxWithContactBuilder).not_to receive(:new)
        expect(Messages::Vk::MessageBuilder).not_to receive(:new)
        
        service.perform
      end

      it 'skips message without from_id' do
        message_data['from_id'] = nil
        
        expect(ContactInboxWithContactBuilder).not_to receive(:new)
        expect(Messages::Vk::MessageBuilder).not_to receive(:new)
        
        service.perform
      end

      it 'skips message from group itself' do
        message_data['from_id'] = channel.group_id.to_i
        
        expect(ContactInboxWithContactBuilder).not_to receive(:new)
        expect(Messages::Vk::MessageBuilder).not_to receive(:new)
        
        service.perform
      end
    end

    context 'with VK API errors' do
      before do
        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/users.get', any_args)
          .and_return(double(
            success?: true,
            parsed_response: {
              'error' => {
                'error_code' => 5,
                'error_msg' => 'User authorization failed'
              }
            }
          ))
      end

      it 'handles authorization error' do
        expect(channel).to receive(:authorization_error!)
        
        expect {
          service.perform
        }.to change { channel.reload.authorization_error_count }.by(1)
      end
    end

    context 'with user fetch failure' do
      before do
        allow(HTTParty).to receive(:get).and_raise(StandardError, 'Network error')
      end

      it 'uses fallback user name' do
        expect(ContactInboxWithContactBuilder).to receive(:new)
          .with({
            source_id: '456',
            inbox: inbox,
            contact_attributes: { name: 'VK User 456' }
          })
          .and_return(double(perform: create(:contact_inbox, inbox: inbox, source_id: '456')))

        expect(Messages::Vk::MessageBuilder).to receive(:new)
          .and_return(double(perform: true))

        service.perform
      end
    end
  end

  describe '#fetch_user_info' do
    let(:user_id) { 456 }

    context 'with successful API response' do
      let(:user_data) do
        {
          'first_name' => 'Jane',
          'last_name' => 'Smith',
          'photo_200' => 'https://example.com/jane.jpg'
        }
      end

      before do
        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/users.get', any_args)
          .and_return(double(
            success?: true,
            parsed_response: { 'response' => [user_data] }
          ))
      end

      it 'returns formatted user info' do
        result = service.send(:fetch_user_info, user_id)
        
        expect(result).to eq({
          name: 'Jane Smith',
          avatar_url: 'https://example.com/jane.jpg'
        })
      end
    end

    context 'with API error' do
      before do
        allow(HTTParty).to receive(:get)
          .with('https://api.vk.com/method/users.get', any_args)
          .and_return(double(
            success?: true,
            parsed_response: {
              'error' => {
                'error_code' => 7,
                'error_msg' => 'Permission denied'
              }
            }
          ))
      end

      it 'returns fallback user info' do
        result = service.send(:fetch_user_info, user_id)
        
        expect(result).to eq({ name: 'VK User 456' })
      end
    end
  end
end