require 'rails_helper'

RSpec.describe Channel::Vk do
  let(:account) { create(:account) }
  
  describe 'validations' do
    it { should validate_presence_of(:access_token) }
    it { should validate_presence_of(:group_id) }
    it { should validate_presence_of(:group_name) }
    it { should validate_uniqueness_of(:group_id).scoped_to(:account_id) }
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_one(:inbox) }
  end

  describe 'callbacks' do
    it 'sets up webhook after creation' do
      expect(Vk::WebhookService).to receive(:new).and_return(double(setup: true))
      create(:channel_vk, account: account)
    end

    it 'removes webhook before destruction' do
      channel = create(:channel_vk, account: account)
      expect(Vk::WebhookService).to receive(:new).and_return(double(remove: true))
      channel.destroy
    end
  end

  describe '#name' do
    it 'returns VK' do
      channel = build(:channel_vk)
      expect(channel.name).to eq('VK')
    end
  end

  describe '#create_contact_inbox' do
    let(:channel) { create(:channel_vk, account: account) }
    let(:inbox) { create(:inbox, channel: channel, account: account) }

    it 'creates a contact inbox' do
      allow(channel).to receive(:inbox).and_return(inbox)
      
      expect(ContactInboxWithContactBuilder).to receive(:new).with({
        source_id: '12345',
        inbox: inbox,
        contact_attributes: { name: 'Test User' }
      }).and_return(double(perform: true))

      channel.create_contact_inbox('12345', 'Test User')
    end
  end

  describe 'with Reauthorizable concern' do
    let(:channel) { create(:channel_vk, account: account) }

    it 'handles authorization errors' do
      expect { channel.authorization_error! }.to change { channel.reload.authorization_error_count }.by(1)
    end

    it 'sets reauthorization required after threshold' do
      channel.update!(authorization_error_count: Channel::Vk::AUTHORIZATION_ERROR_THRESHOLD)
      channel.authorization_error!
      expect(channel.reload.reauthorization_required?).to be true
    end
  end
end