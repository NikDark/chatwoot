require 'rails_helper'

RSpec.describe Vk::SendOnVkService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_vk, account: account) }
  let(:inbox) { create(:inbox, channel: channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '456') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:service) { described_class.new(message: message) }

  describe '#perform_reply' do
    context 'with text message' do
      let(:successful_response) do
        double(
          success?: true,
          parsed_response: { 'response' => 12345 }
        )
      end

      before do
        allow(HTTParty).to receive(:post)
          .with('https://api.vk.com/method/messages.send', any_args)
          .and_return(successful_response)
      end

      it 'sends message to VK' do
        expect(HTTParty).to receive(:post)
          .with(
            'https://api.vk.com/method/messages.send',
            body: {
              peer_id: '456',
              message: message.content,
              random_id: instance_of(Integer),
              access_token: channel.access_token,
              v: '5.131'
            }
          )
          .and_return(successful_response)

        service.send(:perform_reply)

        expect(message.reload.source_id).to eq('12345')
      end

      it 'updates message status to sent' do
        expect(Messages::StatusUpdateService).to receive(:new)
          .with(message, 'sent')
          .and_return(double(perform: true))

        service.send(:perform_reply)
      end
    end

    context 'with VK API error' do
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
        allow(HTTParty).to receive(:post)
          .with('https://api.vk.com/method/messages.send', any_args)
          .and_return(error_response)
      end

      it 'handles authorization error' do
        expect(channel).to receive(:authorization_error!)
        expect(Messages::StatusUpdateService).to receive(:new)
          .with(message, 'failed', 'User authorization failed')
          .and_return(double(perform: true))

        service.send(:perform_reply)
      end
    end

    context 'with HTTP error' do
      let(:failed_response) do
        double(success?: false)
      end

      before do
        allow(HTTParty).to receive(:post)
          .with('https://api.vk.com/method/messages.send', any_args)
          .and_return(failed_response)
      end

      it 'marks message as failed' do
        expect(Messages::StatusUpdateService).to receive(:new)
          .with(message, 'failed', 'HTTP Error')
          .and_return(double(perform: true))

        service.send(:perform_reply)
      end
    end

    context 'with attachments' do
      let(:attachment) { create(:attachment, message: message) }

      before do
        allow(message).to receive(:attachments).and_return([attachment])
        allow(attachment).to receive(:file_type).and_return('image')
        allow(attachment).to receive(:file).and_return(double(filename: 'test.jpg'))
        allow(attachment).to receive(:download_url).and_return('https://example.com/test.jpg')
      end

      it 'sends attachment as text message' do
        expect(HTTParty).to receive(:post).twice # once for content, once for attachment
          .with('https://api.vk.com/method/messages.send', any_args)
          .and_return(double(success?: true, parsed_response: { 'response' => 123 }))

        service.send(:perform_reply)
      end
    end

    context 'with network error' do
      before do
        allow(HTTParty).to receive(:post).and_raise(StandardError, 'Network timeout')
      end

      it 'handles network error' do
        expect(Messages::StatusUpdateService).to receive(:new)
          .with(message, 'failed', 'Network timeout')
          .and_return(double(perform: true))

        service.send(:perform_reply)
      end
    end
  end

  describe '#generate_random_id' do
    it 'generates a random integer' do
      random_id = service.send(:generate_random_id)
      expect(random_id).to be_an(Integer)
      expect(random_id).to be_between(0, 2**31)
    end

    it 'generates different IDs on consecutive calls' do
      id1 = service.send(:generate_random_id)
      id2 = service.send(:generate_random_id)
      expect(id1).not_to eq(id2)
    end
  end

  describe '#handle_api_error' do
    context 'with authorization error (code 5)' do
      let(:error) do
        {
          'error_code' => 5,
          'error_msg' => 'User authorization failed'
        }
      end

      it 'triggers channel authorization error' do
        expect(channel).to receive(:authorization_error!)
        service.send(:handle_api_error, error)
      end
    end

    context 'with permission denied error (code 7)' do
      let(:error) do
        {
          'error_code' => 7,
          'error_msg' => 'Permission to perform this action is denied'
        }
      end

      it 'logs error without triggering authorization error' do
        expect(Rails.logger).to receive(:error)
          .with('VK permission denied: Permission to perform this action is denied')
        
        expect(channel).not_to receive(:authorization_error!)
        service.send(:handle_api_error, error)
      end
    end

    context 'with user blocked messages error (code 901)' do
      let(:error) do
        {
          'error_code' => 901,
          'error_msg' => "Can't send messages for users without permission"
        }
      end

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn)
          .with("VK user blocked messages: Can't send messages for users without permission")
        
        service.send(:handle_api_error, error)
      end
    end
  end
end