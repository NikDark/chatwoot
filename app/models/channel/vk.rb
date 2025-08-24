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

  def create_contact_inbox(vk_user_id, name)
    ContactInboxWithContactBuilder.new({
      source_id: vk_user_id.to_s,
      inbox: inbox,
      contact_attributes: { name: name }
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