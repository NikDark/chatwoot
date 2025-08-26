require 'rails_helper'

RSpec.describe Webhooks::VkEventsJob, type: :job do
  let(:channel) { create(:channel_vk) }
  let(:group_id) { channel.group_id }

  describe '#perform' do
    context 'with message_new event' do
      let(:event_data) do
        {
          'type' => 'message_new',
          'group_id' => group_id,
          'object' => {
            'message' => {
              'id' => 123,
              'from_id' => 456,
              'text' => 'Hello from VK user',
              'date' => Time.current.to_i
            }
          }
        }
      end

      it 'processes incoming message' do
        expect(Vk::MessageTextService).to receive(:new)
          .with(event_data['object']['message'], channel)
          .and_return(double(perform: true))

        described_class.perform_now(event_data)
      end

      it 'skips processing if channel requires reauthorization' do
        channel.update!(reauthorization_required: true)
        
        expect(Vk::MessageTextService).not_to receive(:new)
        
        described_class.perform_now(event_data)
      end

      it 'skips processing if channel not found' do
        event_data['group_id'] = 'nonexistent'
        
        expect(Vk::MessageTextService).not_to receive(:new)
        
        described_class.perform_now(event_data)
      end
    end

    context 'with message_reply event' do
      let(:event_data) do
        {
          'type' => 'message_reply',
          'group_id' => group_id,
          'object' => {
            'message' => {
              'id' => 124,
              'from_id' => group_id.to_i,
              'text' => 'Reply from community',
              'date' => Time.current.to_i
            }
          }
        }
      end

      it 'processes outgoing message confirmation' do
        expect(Rails.logger).to receive(:info)
          .with("VK outgoing message confirmation: 124")

        described_class.perform_now(event_data)
      end
    end

    context 'with unprocessed event type' do
      let(:event_data) do
        {
          'type' => 'unknown_event',
          'group_id' => group_id
        }
      end

      it 'logs unprocessed event' do
        expect(Rails.logger).to receive(:info)
          .with("Unprocessed VK event: unknown_event")

        described_class.perform_now(event_data)
      end
    end

    context 'with mutex lock' do
      let(:event_data) do
        {
          'type' => 'message_new',
          'group_id' => group_id,
          'object' => {
            'message' => {
              'id' => 123,
              'from_id' => 456,
              'text' => 'Test message',
              'date' => Time.current.to_i
            }
          }
        }
      end

      it 'uses mutex lock for message processing' do
        expected_key = format(::Redis::Alfred::VK_MESSAGE_MUTEX, group_id: group_id)
        
        job = described_class.new
        expect(job).to receive(:with_lock).with(expected_key)
        
        job.perform(event_data)
      end
    end
  end
end