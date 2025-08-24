require 'rails_helper'

RSpec.describe Webhooks::VkController, type: :controller do
  let(:channel) { create(:channel_vk) }
  
  describe 'GET #verify' do
    context 'with valid verify token' do
      before do
        allow(GlobalConfigService).to receive(:load)
          .with('VK_VERIFY_TOKEN', '')
          .and_return('test_verify_token')
      end

      it 'returns the challenge' do
        get :verify, params: { 
          'hub.verify_token' => 'test_verify_token',
          'hub.challenge' => 'test_challenge'
        }
        
        expect(response.body).to eq('test_challenge')
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid verify token' do
      it 'does not return the challenge' do
        get :verify, params: { 
          'hub.verify_token' => 'invalid_token',
          'hub.challenge' => 'test_challenge'
        }
        
        expect(response.body).to be_blank
      end
    end
  end

  describe 'POST #events' do
    let(:valid_signature) { 'valid_signature' }
    
    before do
      allow(GlobalConfigService).to receive(:load)
        .with('VK_SECRET_KEY', '')
        .and_return('test_secret')
        
      # Mock signature verification
      allow(Digest::SHA256).to receive(:hexdigest)
        .with('test_secret' + request.raw_post)
        .and_return(valid_signature)
        
      request.headers['X-VK-Signature'] = valid_signature
    end

    context 'with confirmation event' do
      let(:confirmation_params) do
        {
          type: 'confirmation',
          group_id: channel.group_id
        }
      end

      it 'returns confirmation token' do
        post :events, params: confirmation_params, as: :json
        
        expect(response.body).to eq(channel.confirmation_token)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with message_new event' do
      let(:message_params) do
        {
          type: 'message_new',
          group_id: channel.group_id,
          object: {
            message: {
              id: 123,
              from_id: 456,
              text: 'Hello from VK',
              date: Time.current.to_i
            }
          }
        }
      end

      it 'queues VK events job' do
        expect(Webhooks::VkEventsJob).to receive(:perform_later)
          .with(message_params.with_indifferent_access)
        
        post :events, params: message_params, as: :json
        
        expect(response.body).to eq('ok')
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with message_reply event' do
      let(:reply_params) do
        {
          type: 'message_reply',
          group_id: channel.group_id,
          object: {
            message: {
              id: 124,
              from_id: channel.group_id.to_i,
              text: 'Reply from community',
              date: Time.current.to_i
            }
          }
        }
      end

      it 'queues VK events job' do
        expect(Webhooks::VkEventsJob).to receive(:perform_later)
          .with(reply_params.with_indifferent_access)
        
        post :events, params: reply_params, as: :json
        
        expect(response.body).to eq('ok')
      end
    end

    context 'with unhandled event type' do
      let(:unknown_params) do
        {
          type: 'unknown_event',
          group_id: channel.group_id
        }
      end

      it 'returns ok without processing' do
        post :events, params: unknown_params, as: :json
        
        expect(response.body).to eq('ok')
      end
    end
  end

  describe 'signature verification' do
    context 'in production environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(GlobalConfigService).to receive(:load)
          .with('VK_SECRET_KEY', '')
          .and_return('test_secret')
      end

      it 'requires valid signature' do
        post :events, params: { type: 'confirmation' }, as: :json
        
        expect(response).to have_http_status(:unauthorized)
      end

      it 'accepts valid signature' do
        request_body = { type: 'confirmation', group_id: channel.group_id }.to_json
        expected_signature = Digest::SHA256.hexdigest('test_secret' + request_body)
        
        request.headers['X-VK-Signature'] = expected_signature
        allow(controller.request).to receive(:raw_post).and_return(request_body)
        
        post :events, params: { type: 'confirmation', group_id: channel.group_id }, as: :json
        
        expect(response).to have_http_status(:ok)
      end
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
      end

      it 'skips signature verification' do
        post :events, params: { type: 'confirmation', group_id: channel.group_id }, as: :json
        
        expect(response).to have_http_status(:ok)
      end
    end
  end
end