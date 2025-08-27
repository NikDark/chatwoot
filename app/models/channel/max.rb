# == Schema Information
#
# Table name: channel_max
#
#  id         :bigint           not null, primary key
#  bot_name   :string
#  bot_token  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#
# Indexes
#
#  index_channel_max_on_bot_token  (bot_token) UNIQUE
#

class Channel::Max < ApplicationRecord
  include Channelable

  self.table_name = 'channel_max'
  EDITABLE_ATTRS = [:bot_token].freeze

  before_validation :ensure_valid_bot_token, on: :create
  validates :bot_token, presence: true, uniqueness: true
  before_save :setup_max_webhook

  def name
    'MAX'
  end

  def max_api_url
    "https://api.max.ru/bot/#{bot_token}"
  end

  def send_message_on_max(message)
    message_id = send_message(message) if message.outgoing_content.present?
    # attachments support can be added similar to Telegram
    message_id
  end

  def process_error(message, response)
    return unless response.parsed_response['ok'] == false

    message.external_error = "#{response.parsed_response['error_code']}, #{response.parsed_response['description']}"
    message.status = :failed
    message.save!
  end

  def chat_id(message)
    message.conversation[:additional_attributes]['chat_id']
  end

  def reply_to_message_id(message)
    message.content_attributes['in_reply_to_external_id']
  end

  private

  def ensure_valid_bot_token
    response = HTTParty.get("#{max_api_url}/getMe")
    unless response.success?
      errors.add(:bot_token, 'invalid token')
      return
    end

    self.bot_name = response.parsed_response.dig('result', 'username')
  end

  def setup_max_webhook
    HTTParty.post("#{max_api_url}/deleteWebhook")
    response = HTTParty.post("#{max_api_url}/setWebhook",
                             body: {
                               url: "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/max/#{bot_token}"
                             })
    errors.add(:bot_token, 'error setting up the webook') unless response.success?
  end

  def send_message(message)
    response = message_request(
      chat_id(message),
      message.outgoing_content,
      reply_markup(message),
      reply_to_message_id(message)
    )
    process_error(message, response)
    response.parsed_response.dig('result', 'message_id') if response.success?
  end

  def reply_markup(message)
    return unless message.content_type == 'input_select'

    {
      one_time_keyboard: true,
      inline_keyboard: message.content_attributes['items'].map do |item|
        [{
          text: item['title'],
          callback_data: item['value']
        }]
      end
    }.to_json
  end

  def message_request(chat_id, text, reply_markup = nil, reply_to_message_id = nil)
    HTTParty.post("#{max_api_url}/sendMessage",
                  body: {
                    chat_id: chat_id,
                    text: text,
                    reply_markup: reply_markup,
                    reply_to_message_id: reply_to_message_id
                  })
  end
end

