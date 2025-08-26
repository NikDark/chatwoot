FactoryBot.define do
  factory :channel_vk, class: 'Channel::Vk' do
    account
    access_token { SecureRandom.hex(32) }
    group_id { rand(100000..999999).to_s }
    group_name { "VK Community #{rand(1..1000)}" }
    confirmation_token { SecureRandom.hex(16) }
    authorization_error_count { 0 }
    reauthorization_required { false }

    after(:build) do |channel_vk|
      # Mock webhook setup to avoid external API calls
      allow(Vk::WebhookService).to receive(:new).and_return(double(setup: true, remove: true))
    end

    trait :with_error_count do
      authorization_error_count { 2 }
    end

    trait :reauthorization_required do
      reauthorization_required { true }
      authorization_error_count { Channel::Vk::AUTHORIZATION_ERROR_THRESHOLD + 1 }
    end
  end
end