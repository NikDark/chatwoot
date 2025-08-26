class Vk::AutoAssignAdministratorsService
  include HTTParty

  def initialize(inbox)
    @inbox = inbox
    @account = inbox.account
  end

  def perform
    assign_administrators_to_inbox
  end

  private

  attr_reader :inbox, :account

  def assign_administrators_to_inbox
    administrator_ids = account.account_users
                              .joins(:user)
                              .where(role: 'administrator')
                              .where(users: { confirmed_at: Date.current.all_day })
                              .pluck(:user_id)

    return if administrator_ids.empty?

    # Create inbox members for all administrators
    administrator_ids.each do |user_id|
      InboxMember.find_or_create_by(
        inbox: inbox,
        user_id: user_id
      )
    end

    Rails.logger.info "VK Auto-assign: Added #{administrator_ids.count} administrators to inbox #{inbox.id}"
  end
end