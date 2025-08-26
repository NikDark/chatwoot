require 'rails_helper'

RSpec.describe Messages::Vk::MessageBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  
  let(:message_data) do
    {
      'id' => 123,
      'from_id' => 456,
      'text' => 'Hello from VK',
      'date' => Time.current.to_i
    }
  end

  let(:builder) { described_class.new(message_data, inbox, contact_inbox) }

  describe '#perform' do
    context 'with valid message data' do
      before do
        allow(contact_inbox).to receive(:conversation).and_return(conversation)
      end

      it 'creates a message' do
        expect {
          builder.perform
        }.to change(Message, :count).by(1)
      end

      it 'creates message with correct attributes' do
        message = builder.perform

        expect(message.account).to eq(account)
        expect(message.inbox).to eq(inbox)
        expect(message.message_type).to eq('incoming')
        expect(message.content).to eq('Hello from VK')
        expect(message.source_id).to eq('123')
        expect(message.contact).to eq(contact)
        expect(message.sender).to eq(contact)
        expect(message.external_source_id_key).to eq('vk_message_id')
      end

      it 'associates message with conversation' do
        message = builder.perform
        expect(message.conversation).to eq(conversation)
      end
    end

    context 'without conversation' do
      before do
        allow(contact_inbox).to receive(:conversation).and_return(nil)
        allow(contact_inbox).to receive(:create_conversation)
          .with(
            account: account,
            inbox: inbox,
            contact: contact
          )
          .and_return(conversation)
      end

      it 'creates a new conversation' do
        expect(contact_inbox).to receive(:create_conversation)
          .with(
            account: account,
            inbox: inbox,
            contact: contact
          )

        builder.perform
      end

      it 'creates message with new conversation' do
        message = builder.perform
        expect(message.conversation).to eq(conversation)
      end
    end

    context 'with empty message text' do
      before do
        message_data['text'] = ''
      end

      it 'does not create a message' do
        expect {
          builder.perform
        }.not_to change(Message, :count)
      end

      it 'returns nil' do
        result = builder.perform
        expect(result).to be_nil
      end
    end

    context 'with blank message text' do
      before do
        message_data['text'] = '   '
      end

      it 'does not create a message' do
        expect {
          builder.perform
        }.not_to change(Message, :count)
      end
    end

    context 'with nil message text' do
      before do
        message_data['text'] = nil
      end

      it 'does not create a message' do
        expect {
          builder.perform
        }.not_to change(Message, :count)
      end
    end
  end

  describe 'message parameters' do
    let(:message_params) { builder.send(:message_params) }

    before do
      allow(contact_inbox).to receive(:conversation).and_return(conversation)
    end

    it 'includes all required parameters' do
      expect(message_params).to include(
        account: account,
        inbox: inbox,
        message_type: :incoming,
        content: 'Hello from VK',
        source_id: '123',
        contact: contact,
        sender: contact,
        external_source_id_key: 'vk_message_id'
      )
    end
  end
end