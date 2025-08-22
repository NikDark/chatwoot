# Chatwoot VK.com Integration - Ruby Implementation Guide

## Overview

This document provides a comprehensive technical solution for integrating VK.com (VKontakte) into Chatwoot's inbox system using Ruby, following the established patterns of Facebook and Instagram integrations.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [VK API Analysis](#vk-api-analysis)
3. [Ruby Implementation](#ruby-implementation)
4. [Database Schema](#database-schema)
5. [Authentication & OAuth Flow](#authentication--oauth-flow)
6. [Webhook Implementation](#webhook-implementation)
7. [Message Processing Workflow](#message-processing-workflow)
8. [Configuration & Environment Variables](#configuration--environment-variables)
9. [Security Considerations](#security-considerations)
10. [Testing Strategy](#testing-strategy)
11. [Deployment Guide](#deployment-guide)

## Architecture Overview

VK.com integration follows Chatwoot's established channel pattern, identical to Facebook and Instagram integrations. The system supports:

- **VK Communities (Groups)** - Business pages that can receive and send messages
- **Callback API** - VK's webhook system for real-time message delivery
- **OAuth 2.0 Flow** - Standard authorization pattern like other social channels
- **Message Synchronization** - Bidirectional message sync between VK and Chatwoot

### Integration Pattern

The VK integration follows the exact same pattern as Facebook/Instagram:
1. **Channel Model** - `Channel::Vk` similar to `Channel::FacebookPage`
2. **OAuth Controller** - Authorization flow handling
3. **Webhook Controller** - Incoming message processing
4. **Services** - Message sending and processing
5. **Jobs** - Asynchronous webhook event processing

## VK API Analysis

### VK API Capabilities

#### Messaging Features
- `messages.send` - Send messages to users/communities
- `messages.getHistory` - Retrieve message history
- `messages.getConversations` - Get conversation list
- `messages.setActivity` - Set typing indicators
- `messages.markAsRead` - Mark messages as read

#### Webhook Events (Callback API)
- `message_new` - New incoming message
- `message_reply` - New outgoing message
- `message_edit` - Message edited
- `message_allow` - User allowed messages from community
- `message_deny` - User blocked messages from community

#### Authentication Methods
- **Group Token** - For community management (recommended)
- **User Token** - For personal account access
- **Service Token** - For server-side operations

### Available Ruby VK Clients

- **vk-ruby** (https://github.com/7even/vk-ruby) - Basic VK API wrapper
- **Custom HTTP implementation** - Direct API calls using HTTParty (recommended)

## Ruby Implementation

### File Structure

Following Chatwoot's established pattern:

```
app/
├── models/
│   └── channel/
│       └── vk.rb                        # VK channel model
├── controllers/
│   ├── webhooks/
│   │   └── vk_controller.rb             # VK webhook handler
│   ├── vk/
│   │   └── callbacks_controller.rb      # VK OAuth callbacks
│   └── concerns/
│       └── vk_concern.rb                # VK OAuth utilities
├── services/
│   └── vk/
│       ├── send_on_vk_service.rb        # Send messages to VK
│       ├── message_text_service.rb      # Process incoming messages
│       ├── webhook_service.rb           # Webhook management
│       └── base_service.rb              # Base VK service
├── jobs/
│   └── webhooks/
│       └── vk_events_job.rb             # VK webhook event processor
└── builders/
    └── messages/
        └── vk/
            └── message_builder.rb       # VK message builder
```

### 1. VK Channel Model

```ruby
# app/models/channel/vk.rb
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
```

### 2. VK Webhook Controller

```ruby
# app/controllers/webhooks/vk_controller.rb
class Webhooks::VkController < ActionController::API
  before_action :verify_signature

  def verify
    render plain: params['hub.challenge'] if valid_verify_token?
  end

  def events
    Rails.logger.info('VK webhook received events')
    
    case params['type']
    when 'confirmation'
      render plain: confirmation_token
    when 'message_new', 'message_reply'
      Webhooks::VkEventsJob.perform_later(params.to_unsafe_hash)
      render plain: 'ok'
    else
      Rails.logger.warn("Unhandled VK event type: #{params['type']}")
      render plain: 'ok'
    end
  end

  private

  def verify_signature
    return if Rails.env.development?
    
    secret_key = GlobalConfigService.load('VK_SECRET_KEY', '')
    return head :unauthorized if secret_key.blank?
    
    # VK signature verification
    # https://dev.vk.com/api/callback/getting-started#Проверка%20подлинности
    request_body = request.raw_post
    signature = request.headers['X-VK-Signature']
    
    expected_signature = Digest::SHA256.hexdigest(secret_key + request_body)
    
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  def valid_verify_token?
    params['hub.verify_token'] == GlobalConfigService.load('VK_VERIFY_TOKEN', '')
  end

  def confirmation_token
    group_id = params['group_id']
    channel = Channel::Vk.find_by(group_id: group_id)
    channel&.confirmation_token || GlobalConfigService.load('VK_CONFIRMATION_TOKEN', '')
  end
end
```

### 3. VK Events Job

```ruby
# app/jobs/webhooks/vk_events_job.rb
class Webhooks::VkEventsJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  SUPPORTED_EVENTS = [:message_new, :message_reply].freeze

  def perform(event_data)
    @event_data = event_data.with_indifferent_access
    
    group_id = @event_data['group_id']
    key = format(::Redis::Alfred::VK_MESSAGE_MUTEX, group_id: group_id)
    
    with_lock(key) do
      process_event
    end
  end

  private

  def process_event
    case @event_data['type']
    when 'message_new'
      process_incoming_message
    when 'message_reply'
      process_outgoing_message
    else
      Rails.logger.info("Unprocessed VK event: #{@event_data['type']}")
    end
  end

  def process_incoming_message
    message_data = @event_data['object']['message']
    group_id = @event_data['group_id']
    
    channel = Channel::Vk.find_by(group_id: group_id)
    return unless channel

    return if channel.reauthorization_required?
    
    Vk::MessageTextService.new(message_data, channel).perform
  end

  def process_outgoing_message
    # Handle outgoing message confirmations
    # Update message status, handle delivery receipts
    message_data = @event_data['object']['message']
    group_id = @event_data['group_id']
    
    channel = Channel::Vk.find_by(group_id: group_id)
    return unless channel

    # Find and update message status if needed
    Rails.logger.info("VK outgoing message confirmation: #{message_data['id']}")
  end
end
```

### 4. VK Message Processing Service

```ruby
# app/services/vk/message_text_service.rb
class Vk::MessageTextService < Vk::BaseService
  attr_reader :message_data, :channel

  def initialize(message_data, channel)
    @message_data = message_data
    @channel = channel
    super(channel)
  end

  def perform
    return unless valid_message?
    
    ensure_contact_inbox
    create_message if @contact_inbox
  end

  private

  def valid_message?
    message_data['from_id'].present? && 
      message_data['text'].present? &&
      message_data['from_id'] != channel.group_id.to_i # Skip messages from the group itself
  end

  def ensure_contact_inbox
    vk_user_id = message_data['from_id']
    
    @contact_inbox = channel.inbox.contact_inboxes.find_by(source_id: vk_user_id.to_s)
    
    if @contact_inbox.blank?
      user_info = fetch_user_info(vk_user_id)
      @contact_inbox = channel.create_contact_inbox(vk_user_id, user_info[:name])
    end
  end

  def fetch_user_info(user_id)
    response = HTTParty.get(
      'https://api.vk.com/method/users.get',
      query: {
        user_ids: user_id,
        fields: 'first_name,last_name,photo_200',
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    if response.success? && response.parsed_response['response'].present?
      user = response.parsed_response['response'].first
      {
        name: "#{user['first_name']} #{user['last_name']}".strip,
        avatar_url: user['photo_200']
      }
    else
      handle_api_error(response)
      { name: "VK User #{user_id}" }
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch VK user info: #{e.message}")
    { name: "VK User #{user_id}" }
  end

  def create_message
    Messages::Vk::MessageBuilder.new(message_data, channel.inbox).perform
  end

  def handle_api_error(response)
    error = response.parsed_response&.dig('error')
    return unless error

    error_code = error['error_code']
    
    # Handle token expiration
    if error_code == 5 # User authorization failed
      channel.authorization_error!
    end
    
    Rails.logger.error("VK API Error: #{error['error_msg']} (Code: #{error_code})")
  end
end
```

### 5. VK Send Service

```ruby
# app/services/vk/send_on_vk_service.rb
class Vk::SendOnVkService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Vk
  end

  def perform_reply
    send_text_message if message.content.present?
    send_attachments if message.attachments.present?
  rescue StandardError => e
    handle_vk_error(e)
  end

  def send_text_message
    response = HTTParty.post(
      'https://api.vk.com/method/messages.send',
      body: {
        peer_id: contact.get_source_id(inbox.id),
        message: message.content,
        random_id: generate_random_id,
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    handle_send_response(response)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_attachment(attachment)
    end
  end

  def send_attachment(attachment)
    # Upload attachment to VK and send
    case attachment.file_type
    when 'image'
      send_photo_attachment(attachment)
    when 'file'
      send_document_attachment(attachment)
    else
      Rails.logger.warn("Unsupported VK attachment type: #{attachment.file_type}")
    end
  end

  def send_photo_attachment(attachment)
    # VK photo upload process is complex, implement as needed
    Rails.logger.info("Sending VK photo attachment: #{attachment.id}")
  end

  def send_document_attachment(attachment)
    # VK document upload process
    Rails.logger.info("Sending VK document attachment: #{attachment.id}")
  end

  def handle_send_response(response)
    if response.success?
      parsed_response = response.parsed_response
      
      if parsed_response['error']
        handle_api_error(parsed_response['error'])
      elsif parsed_response['response']
        message.update!(source_id: parsed_response['response'].to_s)
        Messages::StatusUpdateService.new(message, 'sent').perform
      end
    else
      Messages::StatusUpdateService.new(message, 'failed', 'HTTP Error').perform
    end
  end

  def handle_api_error(error)
    error_code = error['error_code']
    error_msg = error['error_msg']
    
    case error_code
    when 5 # User authorization failed
      channel.authorization_error!
    when 7 # Permission to perform this action is denied
      Rails.logger.error("VK permission denied: #{error_msg}")
    when 901 # Can't send messages for users without permission
      Rails.logger.warn("VK user blocked messages: #{error_msg}")
    end
    
    Messages::StatusUpdateService.new(message, 'failed', error_msg).perform
  end

  def generate_random_id
    Random.rand(2**31)
  end

  def handle_vk_error(error)
    Rails.logger.error("VK send error: #{error.message}")
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end
end
```

### 6. OAuth Implementation

```ruby
# app/controllers/vk/callbacks_controller.rb
class Vk::CallbacksController < ApplicationController
  include VkConcern

  def show
    return handle_error if params[:error].present?
    
    process_authorization
  rescue StandardError => e
    handle_error(e)
  end

  private

  def process_authorization
    code = params[:code]
    
    token_response = exchange_code_for_token(code)
    group_info = fetch_group_info(token_response['access_token'])
    
    channel = find_or_create_channel(token_response, group_info)
    create_or_update_inbox(channel, group_info)
    
    redirect_to app_vk_inbox_agents_url(
      account_id: current_user.account_id,
      inbox_id: channel.inbox.id
    )
  end

  def exchange_code_for_token(code)
    response = HTTParty.post(
      'https://oauth.vk.com/access_token',
      body: {
        client_id: vk_app_id,
        client_secret: vk_app_secret,
        redirect_uri: vk_callback_url,
        code: code
      }
    )
    
    if response.success?
      response.parsed_response
    else
      raise "Token exchange failed: #{response.body}"
    end
  end

  def fetch_group_info(access_token)
    response = HTTParty.get(
      'https://api.vk.com/method/groups.getById',
      query: {
        access_token: access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      }
    )
    
    if response.success? && response.parsed_response['response']
      response.parsed_response['response'].first
    else
      raise "Failed to fetch group info: #{response.body}"
    end
  end

  def find_or_create_channel(token_response, group_info)
    existing_channel = Channel::Vk.find_by(
      group_id: group_info['id'].to_s,
      account: current_user.account
    )
    
    if existing_channel
      existing_channel.update!(
        access_token: token_response['access_token'],
        group_name: group_info['name']
      )
      existing_channel
    else
      Channel::Vk.create!(
        account: current_user.account,
        access_token: token_response['access_token'],
        group_id: group_info['id'].to_s,
        group_name: group_info['name'],
        confirmation_token: SecureRandom.hex(16)
      )
    end
  end

  def create_or_update_inbox(channel, group_info)
    return if channel.inbox.present?
    
    current_user.account.inboxes.create!(
      account: current_user.account,
      channel: channel,
      name: group_info['name']
    )
  end

  def handle_error(error = nil)
    error_message = error&.message || params[:error_description] || 'Authorization failed'
    
    Rails.logger.error("VK authorization error: #{error_message}")
    
    redirect_to app_new_vk_inbox_url(
      account_id: current_user.account_id,
      error_message: error_message
    )
  end
end
```

### 7. VK Concern

```ruby
# app/controllers/concerns/vk_concern.rb
module VkConcern
  extend ActiveSupport::Concern

  def vk_authorization_url(state)
    params = {
      client_id: vk_app_id,
      redirect_uri: vk_callback_url,
      scope: 'messages,groups',
      response_type: 'code',
      state: state,
      v: GlobalConfigService.load('VK_API_VERSION', '5.131')
    }
    
    "https://oauth.vk.com/authorize?#{params.to_query}"
  end

  private

  def vk_app_id
    GlobalConfigService.load('VK_APP_ID', '')
  end

  def vk_app_secret
    GlobalConfigService.load('VK_APP_SECRET', '')
  end

  def vk_callback_url
    Rails.application.routes.url_helpers.vk_callback_url(
      protocol: Rails.application.config.force_ssl ? 'https' : 'http',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end
end
```

## Database Schema

### VK Channel Table

```ruby
# db/migrate/20240101000000_add_vk_channel.rb
class AddVkChannel < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_vk do |t|
      t.integer :account_id, null: false
      t.string :access_token, null: false
      t.string :group_id, null: false
      t.string :group_name, null: false
      t.string :confirmation_token
      t.integer :authorization_error_count, default: 0
      t.boolean :reauthorization_required, default: false
      t.timestamps
    end

    add_index :channel_vk, :group_id
    add_index :channel_vk, [:account_id, :group_id], unique: true
    add_foreign_key :channel_vk, :accounts, on_delete: :cascade
  end
end
```

## Authentication & OAuth Flow

### VK OAuth Configuration

1. **Create VK Application**
   - Visit https://dev.vk.com/
   - Create new Standalone application
   - Configure redirect URI: `https://your-chatwoot.com/vk/callback`

2. **Required Permissions (Scopes)**
   - `messages` - Send and receive messages
   - `groups` - Manage group messages

### OAuth Flow Steps

1. **Authorization Request** - Redirect user to VK OAuth
2. **Callback Handling** - Process authorization code
3. **Token Exchange** - Get access token
4. **Group Information** - Fetch VK group details
5. **Channel Creation** - Create Chatwoot channel and inbox

## Webhook Implementation

### VK Callback API Setup

```ruby
# app/services/vk/webhook_service.rb
class Vk::WebhookService
  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  def setup
    # Add callback server
    server_id = add_callback_server
    
    # Configure callback settings
    configure_callback_settings(server_id)
    
    Rails.logger.info("VK webhook configured for group #{channel.group_id}")
  end

  def remove
    servers = get_callback_servers
    
    servers.each do |server|
      delete_callback_server(server['id']) if server['url'] == webhook_url
    end
    
    Rails.logger.info("VK webhook removed for group #{channel.group_id}")
  end

  private

  def add_callback_server
    response = api_request('groups.addCallbackServer', {
      group_id: channel.group_id,
      url: webhook_url,
      title: 'Chatwoot Integration',
      secret_key: webhook_secret_key
    })
    
    response['server_id']
  end

  def configure_callback_settings(server_id)
    api_request('groups.setCallbackSettings', {
      group_id: channel.group_id,
      server_id: server_id,
      message_new: 1,
      message_reply: 1
    })
  end

  def get_callback_servers
    response = api_request('groups.getCallbackServers', {
      group_id: channel.group_id
    })
    
    response['items'] || []
  end

  def delete_callback_server(server_id)
    api_request('groups.deleteCallbackServer', {
      group_id: channel.group_id,
      server_id: server_id
    })
  end

  def api_request(method, params)
    response = HTTParty.get(
      "https://api.vk.com/method/#{method}",
      query: params.merge(
        access_token: channel.access_token,
        v: GlobalConfigService.load('VK_API_VERSION', '5.131')
      )
    )
    
    if response.success? && response.parsed_response['response']
      response.parsed_response['response']
    else
      error = response.parsed_response['error']
      raise "VK API Error: #{error['error_msg']} (#{error['error_code']})"
    end
  end

  def webhook_url
    Rails.application.routes.url_helpers.webhooks_vk_url(
      protocol: Rails.application.config.force_ssl ? 'https' : 'http',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end

  def webhook_secret_key
    GlobalConfigService.load('VK_WEBHOOK_SECRET', '')
  end
end
```

## Message Processing Workflow

### Incoming Message Flow

1. **VK Webhook Reception** → `Webhooks::VkController#events`
2. **Event Job Queuing** → `Webhooks::VkEventsJob`
3. **Channel Resolution** → Find VK channel by `group_id`
4. **Message Processing** → `Vk::MessageTextService`
5. **Contact Creation** → Fetch VK user info and create contact
6. **Message Creation** → Build and save message to Chatwoot

### Outgoing Message Flow

1. **Agent Reply** → Chatwoot message created
2. **Send Job** → `SendReplyJob` with VK channel
3. **VK Send Service** → `Vk::SendOnVkService`
4. **VK API Call** → `messages.send` API
5. **Status Update** → Update message status in Chatwoot

## Configuration & Environment Variables

### Required Environment Variables

```bash
# VK Application Configuration
VK_APP_ID=your_vk_app_id
VK_APP_SECRET=your_vk_app_secret
VK_WEBHOOK_SECRET=your_webhook_secret_key

# VK API Configuration
VK_API_VERSION=5.131
VK_VERIFY_TOKEN=your_verify_token
VK_CONFIRMATION_TOKEN=default_confirmation_token

# Chatwoot Configuration
FRONTEND_URL=https://your-chatwoot-instance.com
```

### Routes Configuration

```ruby
# config/routes.rb additions
Rails.application.routes.draw do
  # VK webhook routes
  get 'webhooks/vk', to: 'webhooks/vk#verify'
  post 'webhooks/vk', to: 'webhooks/vk#events'
  
  # VK OAuth callback
  get 'vk/callback', to: 'vk/callbacks#show'
  
  # VK inbox routes
  get 'app/accounts/:account_id/settings/inboxes/new/vk', to: 'dashboard#index', as: 'app_new_vk_inbox'
  get 'app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_vk_inbox_agents'
end
```

## Security Considerations

### 1. Token Security
- Store access tokens encrypted in database
- Implement token validation and refresh mechanisms
- Use secure random generation for webhook secrets

### 2. Webhook Verification
```ruby
def verify_vk_signature(request_body, signature, secret_key)
  expected_signature = Digest::SHA256.hexdigest(secret_key + request_body)
  ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
end
```

### 3. Rate Limiting
- Implement rate limiting for VK API calls
- Handle VK API rate limit responses gracefully
- Use exponential backoff for retries

### 4. Data Privacy
- Implement data retention policies
- Handle user data deletion requests
- Comply with VK's data usage policies

## Testing Strategy

### 1. Unit Tests

```ruby
# spec/models/channel/vk_spec.rb
RSpec.describe Channel::Vk do
  describe 'validations' do
    it { should validate_presence_of(:access_token) }
    it { should validate_presence_of(:group_id) }
    it { should validate_presence_of(:group_name) }
    it { should validate_uniqueness_of(:group_id).scoped_to(:account_id) }
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_one(:inbox) }
  end

  describe 'callbacks' do
    it 'sets up webhook after creation' do
      expect(Vk::WebhookService).to receive(:new).and_call_original
      create(:channel_vk)
    end
  end
end
```

### 2. Integration Tests

```ruby
# spec/controllers/webhooks/vk_controller_spec.rb
RSpec.describe Webhooks::VkController do
  let(:channel) { create(:channel_vk) }
  
  describe 'POST #events' do
    context 'with confirmation event' do
      it 'returns confirmation token' do
        post :events, params: { type: 'confirmation', group_id: channel.group_id }
        expect(response.body).to eq(channel.confirmation_token)
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
        post :events, params: message_params
      end
    end
  end
end
```

## Deployment Guide

### 1. Ruby Implementation Deployment

```bash
# Add to Gemfile
echo 'gem "httparty"' >> Gemfile
bundle install

# Run migration
rails db:migrate

# Set environment variables
export VK_APP_ID=your_app_id
export VK_APP_SECRET=your_app_secret
export VK_WEBHOOK_SECRET=your_secret

# Restart application
systemctl restart chatwoot
```

### 2. Redis Keys Configuration

Add VK-specific Redis keys:

```ruby
# lib/redis/redis_keys.rb
module Redis::Alfred
  # ... existing keys
  VK_MESSAGE_MUTEX = 'vk:message_mutex:%{group_id}'.freeze
end
```

### 3. Monitoring & Logging

```ruby
# Add VK-specific logging
Rails.logger.tagged('VK') do |logger|
  logger.info 'VK webhook received'
end
```

### 4. Health Checks

```ruby
# app/controllers/health_controller.rb
def vk
  # Check VK API connectivity
  response = HTTParty.get(
    'https://api.vk.com/method/users.get',
    query: {
      user_ids: 1,
      access_token: 'test_token',
      v: '5.131'
    }
  )
  
  if response.success?
    render json: { status: 'healthy', service: 'vk' }
  else
    render json: { status: 'unhealthy', service: 'vk' }, status: 503
  end
end
```

## Conclusion

This Ruby implementation guide provides a comprehensive solution for integrating VK.com into Chatwoot following the established patterns of Facebook and Instagram integrations. The implementation ensures:

- **Consistency** with existing Chatwoot channel patterns
- **Robust error handling** and reauthorization support  
- **Secure token management** and webhook verification
- **Comprehensive testing** coverage
- **Scalable architecture** for production deployment

The solution supports VK Communities with proper OAuth flow, webhook handling, and bidirectional message synchronization between VK and Chatwoot platforms, maintaining the same user experience as other social media integrations.
