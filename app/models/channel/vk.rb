# == Schema Information
#
# Table name: channel_vk
#
#  id                        :bigint           not null, primary key
#  access_token              :string           not null
#  authorization_error_count :integer          default(0)
#  confirmation_token        :string
#  group_id                  :string           not null
#  group_name                :string           not null
#  reauthorization_required  :boolean          default(FALSE)
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :integer          not null
#
# Indexes
#
#  index_channel_vk_on_account_id_and_group_id  (account_id,group_id) UNIQUE
#  index_channel_vk_on_group_id                 (group_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#

class Channel::Vk < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_vk'

  AUTHORIZATION_ERROR_THRESHOLD = 3

  validates :access_token, presence: true
  validates :group_id, presence: true, uniqueness: { scope: :account_id }
  validates :group_name, presence: true

  after_create_commit :setup_webhook
  before_destroy :remove_webhook

  def name
    'VK'
  end

  def create_contact_inbox(vk_user_id, user_info)
    # Extract name and additional attributes from user_info
    name = user_info[:name] || user_info['name'] || "VK User #{vk_user_id}"

    contact_attributes = { name: name }

    # Add additional contact attributes if available
    if user_info[:phone].present?
      contact_attributes[:phone_number] = user_info[:phone]
    end

    if user_info[:email].present?
      contact_attributes[:email] = user_info[:email]
    end

    # Add custom attributes for VK-specific fields
    additional_attributes = {}
    additional_attributes['vk_sex'] = user_info[:sex] if user_info[:sex].present?
    additional_attributes['vk_verified'] = user_info[:verified] if user_info[:verified].present?
    additional_attributes['vk_birthday'] = user_info[:birthday] if user_info[:birthday].present?

    if additional_attributes.any?
      contact_attributes[:additional_attributes] = additional_attributes
    end

    ContactInboxWithContactBuilder.new({
      source_id: vk_user_id.to_s,
      inbox: inbox,
      contact_attributes: contact_attributes
    }).perform
  end

  def setup_webhook
    Vk::WebhookService.new(self).setup
  rescue StandardError => e
    Rails.logger.error("VK webhook setup failed: #{e.message}")
  end

  def remove_webhook
    Vk::WebhookService.new(self).remove
  rescue StandardError => e
    Rails.logger.error("VK webhook removal failed: #{e.message}")
  end

  private

  def webhook_url
    Rails.application.routes.url_helpers.webhooks_vk_url(
      protocol: Rails.application.config.force_ssl ? 'https' : 'http',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end
end
