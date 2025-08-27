require 'rails_helper'

RSpec.describe 'Webhooks::MaxController', type: :request do
  describe 'POST /webhooks/max/{:bot_token}' do
    it 'call the max events job with the params' do
      allow(Webhooks::MaxEventsJob).to receive(:perform_later)
      expect(Webhooks::MaxEventsJob).to receive(:perform_later)
      post '/webhooks/max/random_bot_token', params: { content: 'hello' }
      expect(response).to have_http_status(:success)
    end
  end
end

