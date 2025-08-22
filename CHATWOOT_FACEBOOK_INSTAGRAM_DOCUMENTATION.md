# Chatwoot Facebook/Instagram Integration Documentation

## Overview

This document provides a comprehensive overview of how Chatwoot implements Facebook and Instagram integrations using Ruby. It covers the architecture, key management, callback handling, and inbox workflow.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Channel Models](#channel-models)
3. [Key Management & Configuration](#key-management--configuration)
4. [OAuth & Authorization Flow](#oauth--authorization-flow)
5. [Webhook & Callback Implementation](#webhook--callback-implementation)
6. [Message Processing Workflow](#message-processing-workflow)
7. [Inbox Integration](#inbox-integration)
8. [Error Handling](#error-handling)
9. [Configuration Variables](#configuration-variables)

## Architecture Overview

Chatwoot supports two main Meta (Facebook) integrations:

1. **Facebook Pages** (`Channel::FacebookPage`) - Traditional Facebook Messenger integration
2. **Instagram Direct** (`Channel::Instagram`) - Instagram messaging integration

Both integrations share similar patterns but have distinct implementations for their respective APIs.

### Key Ruby Files Structure

```
app/
├── models/
│   └── channel/
│       ├── facebook_page.rb          # Facebook Page channel model
│       └── instagram.rb              # Instagram channel model
├── controllers/
│   ├── webhooks/
│   │   └── instagram_controller.rb   # Instagram webhook handler
│   ├── instagram/
│   │   └── callbacks_controller.rb   # Instagram OAuth callbacks
│   └── concerns/
│       ├── instagram_concern.rb      # Instagram OAuth utilities
│       └── meta_token_verify_concern.rb # Meta token verification
├── services/
│   ├── facebook/
│   │   └── send_on_facebook_service.rb # Facebook message sending
│   └── instagram/
│       ├── refresh_oauth_token_service.rb # Token refresh logic
│       ├── message_text.rb           # Instagram message processing
│       ├── send_on_instagram_service.rb # Instagram message sending
│       └── base_message_text.rb      # Base message processing
├── jobs/
│   └── webhooks/
│       └── instagram_events_job.rb   # Instagram webhook event processor
└── builders/
    ├── contact_inbox_with_contact_builder.rb # Contact/inbox creation
    └── messages/
        └── instagram/
            └── message_builder.rb    # Instagram message builder
```

## Channel Models

### Facebook Page Channel (`Channel::FacebookPage`)

```ruby
# Location: app/models/channel/facebook_page.rb
class Channel::FacebookPage < ApplicationRecord
  include Channelable
  include Reauthorizable

  # Database schema
  # - page_id: string (Facebook Page ID)
  # - page_access_token: string (Page access token)
  # - user_access_token: string (User access token)
  # - instagram_id: string (Connected Instagram account ID)
  # - account_id: integer (Chatwoot account)
```

**Key Features:**
- Manages Facebook Page access tokens
- Supports Instagram integration via Facebook Page
- Automatic webhook subscription/unsubscription
- Token validation and reauthorization

### Instagram Channel (`Channel::Instagram`)

```ruby
# Location: app/models/channel/instagram.rb
class Channel::Instagram < ApplicationRecord
  include Channelable
  include Reauthorizable

  # Database schema
  # - instagram_id: string (Instagram account ID)
  # - access_token: string (Instagram access token)
  # - expires_at: datetime (Token expiration)
  # - account_id: integer (Chatwoot account)
```

**Key Features:**
- Direct Instagram API integration
- Long-lived token management (60-day validity)
- Automatic token refresh
- Webhook subscription management

## Key Management & Configuration

### Configuration Storage

Chatwoot uses `GlobalConfigService` to manage configuration keys loaded from environment variables:

```ruby
# Instagram Configuration
INSTAGRAM_APP_ID=your_instagram_app_id
INSTAGRAM_APP_SECRET=your_instagram_app_secret
INSTAGRAM_VERIFY_TOKEN=your_webhook_verify_token
INSTAGRAM_API_VERSION=v22.0

# Facebook Configuration
FB_APP_ID=your_facebook_app_id
FB_APP_SECRET=your_facebook_app_secret
FB_VERIFY_TOKEN=your_webhook_verify_token
IG_VERIFY_TOKEN=your_instagram_via_facebook_verify_token
FACEBOOK_API_VERSION=v17.0
```

### Token Storage Locations

1. **Database Storage:**
   - `channel_facebook_pages.page_access_token` - Facebook Page tokens
   - `channel_facebook_pages.user_access_token` - Facebook User tokens
   - `channel_instagram.access_token` - Instagram access tokens
   - `channel_instagram.expires_at` - Token expiration timestamps

2. **Configuration Service:**
   - App credentials and secrets via `GlobalConfigService.load()`
   - Webhook verification tokens
   - API version configurations

### Token Refresh Mechanism

Instagram tokens require periodic refresh (every 60 days):

```ruby
# Location: app/services/instagram/refresh_oauth_token_service.rb
class Instagram::RefreshOauthTokenService
  def access_token
    return unless token_valid?
    return channel[:access_token] unless token_eligible_for_refresh?
    
    attempt_token_refresh
  end

  private

  def token_eligible_for_refresh?
    # Three conditions must be met:
    # 1. Token is still valid
    token_is_valid = Time.current < channel.expires_at
    # 2. Token is at least 24 hours old
    token_is_old_enough = channel.updated_at.present? && Time.current - channel.updated_at >= 24.hours
    # 3. Token is approaching expiry (within 10 days)
    approaching_expiry = channel.expires_at < 10.days.from_now

    token_is_valid && token_is_old_enough && approaching_expiry
  end
end
```

## OAuth & Authorization Flow

### Instagram OAuth Flow

1. **Authorization URL Generation:**
```ruby
# Location: app/controllers/concerns/instagram_concern.rb
def instagram_client
  ::OAuth2::Client.new(
    client_id,
    client_secret,
    {
      site: 'https://api.instagram.com',
      authorize_url: 'https://api.instagram.com/oauth/authorize',
      token_url: 'https://api.instagram.com/oauth/access_token'
    }
  )
end
```

2. **Callback Handling:**
```ruby
# Location: app/controllers/instagram/callbacks_controller.rb
# Route: GET /instagram/callback
def show
  # Handle authorization errors (user cancellation)
  return handle_authorization_error if params[:error].present?
  
  # Process successful authorization
  process_successful_authorization
end

private

def process_successful_authorization
  # Exchange authorization code for access token
  @response = instagram_client.auth_code.get_token(
    oauth_code,
    redirect_uri: "#{base_url}/instagram/callback",
    grant_type: 'authorization_code'
  )

  # Exchange short-lived token for long-lived token
  @long_lived_token_response = exchange_for_long_lived_token(@response.token)
  
  # Create or update inbox
  inbox, already_exists = find_or_create_inbox
end
```

3. **Long-lived Token Exchange:**
```ruby
def exchange_for_long_lived_token(short_lived_token)
  endpoint = 'https://graph.instagram.com/access_token'
  params = {
    grant_type: 'ig_exchange_token',
    client_secret: client_secret,
    access_token: short_lived_token,
    client_id: client_id
  }
  
  make_api_request(endpoint, params, 'Failed to exchange token')
end
```

## Webhook & Callback Implementation

### Webhook Routes

```ruby
# Location: config/routes.rb
get 'webhooks/instagram', to: 'webhooks/instagram#verify'
post 'webhooks/instagram', to: 'webhooks/instagram#events'
```

### Instagram Webhook Controller

```ruby
# Location: app/controllers/webhooks/instagram_controller.rb
class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  def events
    return unless params['object'].casecmp('instagram').zero?
    
    entry_params = params.to_unsafe_hash[:entry]
    
    if contains_echo_event?(entry_params)
      # Delay echo events to prevent race conditions
      ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(entry_params)
    else
      ::Webhooks::InstagramEventsJob.perform_later(entry_params)
    end
  end

  private

  def valid_token?(token)
    # Validates against both IG_VERIFY_TOKEN and INSTAGRAM_VERIFY_TOKEN
    token == GlobalConfigService.load('IG_VERIFY_TOKEN', '') ||
      token == GlobalConfigService.load('INSTAGRAM_VERIFY_TOKEN', '')
  end
end
```

### Webhook Event Processing

```ruby
# Location: app/jobs/webhooks/instagram_events_job.rb
class Webhooks::InstagramEventsJob < MutexApplicationJob
  SUPPORTED_EVENTS = [:message, :read].freeze

  def perform(entries)
    key = format(::Redis::Alfred::IG_MESSAGE_MUTEX, sender_id: sender_id, ig_account_id: ig_account_id)
    with_lock(key) do
      process_entries(entries)
    end
  end

  private

  def process_messages(entry)
    messages(entry).each do |messaging|
      instagram_id = instagram_id(messaging)
      channel = find_channel(instagram_id)
      next if channel.blank?

      if (event_name = event_name(messaging))
        send(event_name, messaging, channel)
      end
    end
  end

  def find_channel(instagram_id)
    # Priority: Instagram channel first, then Facebook page fallback
    channel = Channel::Instagram.find_by(instagram_id: instagram_id)
    channel ||= Channel::FacebookPage.find_by(instagram_id: instagram_id)
    channel
  end
end
```

## Message Processing Workflow

### Incoming Message Flow

1. **Webhook Reception:** Instagram sends webhook to `/webhooks/instagram`
2. **Event Job Queuing:** `InstagramEventsJob` processes the webhook payload
3. **Channel Resolution:** Find appropriate channel (Instagram or Facebook Page)
4. **Message Processing:** Route to appropriate message processor
5. **Contact/Inbox Creation:** Create or find existing contact and conversation
6. **Message Creation:** Build and save the message to the database

### Message Processing Services

```ruby
# Location: app/services/instagram/base_message_text.rb
class Instagram::BaseMessageText < Instagram::WebhooksBaseService
  def perform
    connected_instagram_id, contact_id = instagram_and_contact_ids
    inbox_channel(connected_instagram_id)
    
    return if @inbox.blank?
    return if @inbox.channel.reauthorization_required?
    return unsend_message if message_is_deleted?
    
    ensure_contact(contact_id) if contacts_first_message?(contact_id)
    create_message
  end
end
```

### Contact and Inbox Creation

```ruby
# Location: app/builders/contact_inbox_with_contact_builder.rb
class ContactInboxWithContactBuilder
  def perform
    find_or_create_contact_and_contact_inbox
  end

  private

  def find_or_create_contact_and_contact_inbox
    @contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id) if source_id.present?
    return @contact_inbox if @contact_inbox

    ActiveRecord::Base.transaction(requires_new: true) do
      build_contact_with_contact_inbox
    end
    
    update_contact_avatar(@contact) unless @contact.avatar.attached?
    @contact_inbox
  end

  def find_contact_by_instagram_source_id(instagram_id)
    # Reuse existing contact from Facebook channels
    existing_contact_inbox = ContactInbox.joins(:inbox)
                                         .where(source_id: instagram_id)
                                         .where(
                                           'inboxes.channel_type = ? AND inboxes.account_id = ?',
                                           'Channel::FacebookPage',
                                           account.id
                                         ).first
    existing_contact_inbox&.contact
  end
end
```

## Inbox Integration

### Outgoing Messages

#### Facebook Page Messages

```ruby
# Location: app/services/facebook/send_on_facebook_service.rb
class Facebook::SendOnFacebookService < Base::SendOnChannelService
  def perform_reply
    send_message_to_facebook fb_text_message_params if message.content.present?
    
    message.attachments.each do |attachment|
      send_message_to_facebook fb_attachment_message_params(attachment)
    end
  end

  private

  def deliver_message(delivery_params)
    result = Facebook::Messenger::Bot.deliver(delivery_params, page_id: channel.page_id)
    JSON.parse(result)
  end
end
```

#### Instagram Messages

```ruby
# Location: app/services/instagram/send_on_instagram_service.rb
class Instagram::SendOnInstagramService < Instagram::BaseSendService
  def send_message(message_content)
    access_token = channel.access_token
    instagram_id = channel.instagram_id.presence || 'me'

    response = HTTParty.post(
      "https://graph.instagram.com/v22.0/#{instagram_id}/messages",
      body: message_content,
      query: { access_token: access_token }
    )

    process_response(response, message_content)
  end
end
```

### Webhook Subscriptions

#### Facebook Page Subscription

```ruby
# Location: app/models/channel/facebook_page.rb
def subscribe
  Facebook::Messenger::Subscriptions.subscribe(
    access_token: page_access_token,
    subscribed_fields: %w[
      messages message_deliveries message_echoes message_reads standby messaging_handovers
    ]
  )
end
```

#### Instagram Subscription

```ruby
# Location: app/models/channel/instagram.rb
def subscribe
  HTTParty.post(
    "https://graph.instagram.com/v22.0/#{instagram_id}/subscribed_apps",
    query: {
      subscribed_fields: %w[messages message_reactions messaging_seen],
      access_token: access_token
    }
  )
end
```

## Error Handling

### Authorization Errors

Both Facebook and Instagram channels implement the `Reauthorizable` concern:

```ruby
# Location: app/models/concerns/reauthorizable.rb
module Reauthorizable
  def authorization_error!
    update!(authorization_error_count: authorization_error_count + 1)
    reauthorization_required! if authorization_error_count >= self.class::AUTHORIZATION_ERROR_THRESHOLD
  end

  def reauthorization_required!
    update!(reauthorization_required: true)
    # Disable inbox and notify administrators
  end
end
```

### Common Error Scenarios

1. **Token Expiration (Error Code 190):**
   - Automatically triggers reauthorization flow
   - Channel marked as requiring reauthorization

2. **User Consent Required (Error Code 230):**
   - Occurs when Instagram account messages users who haven't initiated contact
   - Safely ignored in processing

3. **Invalid Instagram User (Error Code 9010):**
   - Facebook's validation bot testing
   - Creates "Unknown" contact to maintain flow

## Configuration Variables

### Required Environment Variables

```bash
# Instagram Direct Integration
INSTAGRAM_APP_ID=your_instagram_app_id
INSTAGRAM_APP_SECRET=your_instagram_app_secret
INSTAGRAM_VERIFY_TOKEN=your_webhook_verify_token
INSTAGRAM_API_VERSION=v22.0

# Facebook Page Integration
FB_APP_ID=your_facebook_app_id
FB_APP_SECRET=your_facebook_app_secret
FB_VERIFY_TOKEN=your_webhook_verify_token
FACEBOOK_API_VERSION=v17.0

# Instagram via Facebook Page
IG_VERIFY_TOKEN=your_instagram_via_facebook_verify_token

# General Configuration
FRONTEND_URL=https://your-chatwoot-instance.com
ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT=true
```

### Optional Configuration

```bash
# Feature Flags
ENABLE_INBOX_EVENTS=true
DISABLE_GRAVATAR=false

# API Versions (with defaults)
WHATSAPP_API_VERSION=v22.0  # Used for WhatsApp integration
```

## Security Considerations

1. **Token Storage:** All access tokens are stored encrypted in the database
2. **Webhook Verification:** All webhooks are verified using the configured verify tokens
3. **App Secret Proof:** Facebook requests include app secret proof for additional security
4. **HTTPS Required:** All webhook URLs must use HTTPS in production
5. **Token Rotation:** Instagram tokens are automatically refreshed before expiration

## Debugging and Monitoring

### Key Log Locations

- Webhook events: `Rails.logger.info("Instagram webhook received events")`
- Token refresh: `Rails.logger.error("Token refresh failed: #{e.message}")`
- API errors: `Rails.logger.warn("[InstagramUserFetchError]: #{error_message}")`
- Channel errors: `ChatwootExceptionTracker.new(exception).capture_exception`

### Common Troubleshooting

1. **Webhook Not Receiving Events:**
   - Verify webhook URL is accessible and returns 200 OK
   - Check verify token matches configuration
   - Ensure HTTPS is enabled

2. **Authorization Failures:**
   - Check app credentials in environment variables
   - Verify app is approved for production use
   - Ensure proper permissions are requested

3. **Token Expiration:**
   - Monitor `expires_at` timestamps
   - Check automatic refresh is working
   - Verify long-lived token exchange

This documentation provides a comprehensive overview of Chatwoot's Facebook and Instagram integration implementation in Ruby. The system is designed to be robust, scalable, and maintainable while handling the complexities of Meta's APIs and OAuth flows.