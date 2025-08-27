require 'rails_helper'

RSpec.describe Webhooks::MaxEventsJob do
  let(:account) { create(:account) }
  let(:channel) { Channel::Max.create!(account: account, bot_token: 'abc') }

  it 'skips when channel not found' do
    expect { described_class.perform_now({ bot_token: 'missing' }) }.not_to raise_error
  end

  it 'processes event when params present' do
    allow(Max::IncomingMessageService).to receive(:new).and_call_original
    params = { bot_token: channel.bot_token, max: { message: { text: 'hi', chat: { id: 1 }, from: { id: 2 } } } }
    described_class.perform_now(params)
    expect(Max::IncomingMessageService).to have_received(:new)
  end
end

