# Chatwoot VK.com Integration - Technical Solution

## Overview

This document provides a comprehensive technical solution for integrating VK.com (VKontakte) into Chatwoot's inbox system. The solution covers both Ruby-native integration and Python microservice approaches, following Chatwoot's established patterns for channel integrations.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [VK API Analysis](#vk-api-analysis)
3. [Ruby Implementation (Recommended)](#ruby-implementation-recommended)
4. [Python Microservice Implementation](#python-microservice-implementation)
5. [Database Schema](#database-schema)
6. [Authentication & OAuth Flow](#authentication--oauth-flow)
7. [Webhook Implementation](#webhook-implementation)
8. [Message Processing Workflow](#message-processing-workflow)
9. [Configuration & Environment Variables](#configuration--environment-variables)
10. [Security Considerations](#security-considerations)
11. [Testing Strategy](#testing-strategy)
12. [Deployment Guide](#deployment-guide)

## Architecture Overview

VK.com integration will follow Chatwoot's channel pattern, similar to existing Facebook and Instagram integrations. The system will support:

- **VK Communities (Groups)** - Business pages that can receive and send messages
- **VK Personal Messages** - Direct user-to-user messaging (limited by VK API)
- **Callback API** - VK's webhook system for real-time message delivery
- **Long Poll API** - Alternative method for receiving messages

### Integration Approaches

1. **Ruby Native Integration** (Recommended)
   - Follows existing Chatwoot patterns
   - Easier maintenance and deployment
   - Consistent with codebase architecture

2. **Python Microservice**
   - Leverages mature Python VK clients
   - Separate service communication via HTTP/gRPC
   - More complex deployment but allows language specialization

## VK API Analysis

### Available VK API Clients

#### Ruby Clients
- **vk-ruby** (https://github.com/7even/vk-ruby) - Basic VK API wrapper
- **Custom implementation** - Direct HTTP API calls

#### Python Clients
- **vk_api** (https://github.com/python273/vk_api) - Most mature and feature-rich
- **vkbottle** (https://github.com/vkbottle/vkbottle) - Modern async framework
- **pyvk** (https://github.com/dimka665/vk) - Lightweight wrapper

### VK API Capabilities

#### Messaging Features
- `messages.send` - Send messages to users/groups
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
- **User Token** - For personal account access
- **Group Token** - For community management
- **Service Token** - For server-side operations

## Ruby Implementation (Recommended)

### File Structure

```
app/
├── models/
│   └── channel/
│       └── vk.rb                    # VK channel model
├── controllers/
│   ├── webhooks/
│   │   └── vk_controller.rb         # VK webhook handler
│   ├── vk/
│   │   └── callbacks_controller.rb  # VK OAuth callbacks
│   └── concerns/
│       └── vk_concern.rb            # VK OAuth utilities
├── services/
│   └── vk/
│       ├── send_on_vk_service.rb    # Send messages to VK
│       ├── message_text_service.rb  # Process incoming messages
│       ├── oauth_service.rb         # Handle OAuth flow
│       └── webhook_service.rb       # Process webhook events
├── jobs/
│   └── webhooks/
│       └── vk_events_job.rb         # VK webhook event processor
└── builders/
    └── messages/
        └── vk/
            └── message_builder.rb   # VK message builder
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
  
  def events
    Rails.logger.info('VK webhook received events')
    
    case params['type']
    when 'confirmation'
      render plain: confirmation_token
    when 'message_new', 'message_reply'
      Webhooks::VkEventsJob.perform_later(params.to_unsafe_hash)
      render json: { ok: true }
    else
      Rails.logger.warn("Unhandled VK event type: #{params['type']}")
      render json: { ok: true }
    end
  end

  private

  def verify_signature
    return if Rails.env.development?
    
    # VK signature verification logic
    secret_key = GlobalConfigService.load('VK_SECRET_KEY', '')
    return head :unauthorized if secret_key.blank?
    
    # Implement VK signature verification
    # https://dev.vk.com/api/callback/getting-started#Проверка%20подлинности
  end

  def confirmation_token
    # Return group-specific confirmation token
    group_id = params['group_id']
    channel = Channel::Vk.find_by(group_id: group_id)
    channel&.confirmation_token || GlobalConfigService.load('VK_CONFIRMATION_TOKEN', '')
  end
end
```

### 3. VK Events Job

```ruby
# app/jobs/webhooks/vk_events_job.rb
class Webhooks::VkEventsJob < ApplicationJob
  queue_as :default

  def perform(event_data)
    @event_data = event_data.with_indifferent_access
    
    case @event_data['type']
    when 'message_new'
      process_incoming_message
    when 'message_reply'
      process_outgoing_message
    else
      Rails.logger.info("Unprocessed VK event: #{@event_data['type']}")
    end
  end

  private

  def process_incoming_message
    message_data = @event_data['object']['message']
    group_id = @event_data['group_id']
    
    channel = Channel::Vk.find_by(group_id: group_id)
    return unless channel
    
    Vk::MessageTextService.new(message_data, channel).perform
  end

  def process_outgoing_message
    # Handle outgoing message confirmations
    # Update message status, handle delivery receipts
  end
end
```

### 4. VK Message Processing Service

```ruby
# app/services/vk/message_text_service.rb
class Vk::MessageTextService
  attr_reader :message_data, :channel

  def initialize(message_data, channel)
    @message_data = message_data
    @channel = channel
  end

  def perform
    return unless valid_message?
    
    ensure_contact_inbox
    create_message if @contact_inbox
  end

  private

  def valid_message?
    message_data['from_id'].present? && message_data['text'].present?
  end

  def ensure_contact_inbox
    vk_user_id = message_data['from_id']
    return if vk_user_id == channel.group_id.to_i # Skip messages from the group itself
    
    @contact_inbox = channel.inbox.contact_inboxes.find_by(source_id: vk_user_id.to_s)
    
    if @contact_inbox.blank?
      user_info = fetch_user_info(vk_user_id)
      @contact_inbox = channel.create_contact_inbox(vk_user_id, user_info[:name])
    end
  end

  def fetch_user_info(user_id)
    # Call VK API to get user information
    response = vk_api_client.users.get(
      user_ids: user_id,
      fields: 'first_name,last_name,photo_200'
    )
    
    user = response.first
    {
      name: "#{user['first_name']} #{user['last_name']}".strip,
      avatar_url: user['photo_200']
    }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch VK user info: #{e.message}")
    { name: "VK User #{user_id}" }
  end

  def create_message
    Messages::Vk::MessageBuilder.new(message_data, channel.inbox).perform
  end

  def vk_api_client
    @vk_api_client ||= VK::Application.new(
      app_id: GlobalConfigService.load('VK_APP_ID', ''),
      app_secret: GlobalConfigService.load('VK_APP_SECRET', ''),
      access_token: channel.access_token
    )
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
  end

  def send_text_message
    response = vk_api_client.messages.send(
      peer_id: contact.get_source_id(inbox.id),
      message: message.content,
      random_id: generate_random_id
    )
    
    message.update!(source_id: response.to_s) if response
  rescue StandardError => e
    handle_vk_error(e)
  end

  def send_attachments
    message.attachments.each do |attachment|
      send_attachment(attachment)
    end
  end

  def send_attachment(attachment)
    # Upload attachment to VK and send
    # Implementation depends on attachment type
  end

  def vk_api_client
    @vk_api_client ||= VK::Application.new(
      app_id: GlobalConfigService.load('VK_APP_ID', ''),
      app_secret: GlobalConfigService.load('VK_APP_SECRET', ''),
      access_token: channel.access_token
    )
  end

  def generate_random_id
    Random.rand(2**31)
  end

  def handle_vk_error(error)
    Rails.logger.error("VK send error: #{error.message}")
    
    # Handle specific VK errors
    if error.message.include?('access_token')
      channel.authorization_error!
    end
    
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
    # Implement VK OAuth token exchange
    # https://dev.vk.com/api/access-token/authcode-flow-user
  end

  def fetch_group_info(access_token)
    # Fetch group/community information
  end

  def find_or_create_channel(token_response, group_info)
    # Create or update VK channel
  end
end
```

## Python Microservice Implementation

### Architecture

```
vk-service/
├── app/
│   ├── main.py                 # FastAPI application
│   ├── models/
│   │   ├── vk_client.py        # VK API client wrapper
│   │   └── message.py          # Message models
│   ├── services/
│   │   ├── webhook_service.py  # Handle VK webhooks
│   │   ├── message_service.py  # Process messages
│   │   └── chatwoot_service.py # Communicate with Chatwoot
│   └── config.py               # Configuration
├── requirements.txt
└── Dockerfile
```

### 1. FastAPI Application

```python
# vk-service/app/main.py
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
import vk_api
import httpx
import hashlib
import hmac
from typing import Dict, Any

app = FastAPI()

class VKWebhookEvent(BaseModel):
    type: str
    object: Dict[Any, Any] = None
    group_id: int
    event_id: str = None
    v: str = None
    secret: str = None

@app.post("/vk/webhook/{group_id}")
async def handle_vk_webhook(group_id: int, event: VKWebhookEvent):
    # Verify signature
    if not verify_signature(event):
        raise HTTPException(status_code=401, detail="Invalid signature")
    
    if event.type == "confirmation":
        # Return confirmation token for group
        return await get_confirmation_token(group_id)
    
    elif event.type in ["message_new", "message_reply"]:
        # Process message
        await process_message(event)
        return {"ok": True}
    
    return {"ok": True}

async def verify_signature(event: VKWebhookEvent) -> bool:
    # Implement VK signature verification
    pass

async def get_confirmation_token(group_id: int) -> str:
    # Get confirmation token from Chatwoot or config
    pass

async def process_message(event: VKWebhookEvent):
    # Process the message and send to Chatwoot
    message_service = MessageService()
    await message_service.process_vk_message(event)
```

### 2. VK Client Wrapper

```python
# vk-service/app/models/vk_client.py
import vk_api
from vk_api.longpoll import VkLongPoll, VkEventType
import logging

class VKClient:
    def __init__(self, access_token: str, group_id: int):
        self.access_token = access_token
        self.group_id = group_id
        self.session = vk_api.VkApi(token=access_token)
        self.api = self.session.get_api()
        self.longpoll = VkLongPoll(self.session, group_id=group_id)
    
    def send_message(self, peer_id: int, message: str, attachments=None):
        """Send message to VK user"""
        try:
            return self.api.messages.send(
                peer_id=peer_id,
                message=message,
                random_id=vk_api.utils.get_random_id(),
                attachment=attachments
            )
        except Exception as e:
            logging.error(f"Failed to send VK message: {e}")
            raise
    
    def get_user_info(self, user_id: int):
        """Get user information"""
        try:
            users = self.api.users.get(
                user_ids=[user_id],
                fields='first_name,last_name,photo_200'
            )
            return users[0] if users else None
        except Exception as e:
            logging.error(f"Failed to get VK user info: {e}")
            return None
    
    def upload_photo(self, photo_path: str):
        """Upload photo for messaging"""
        upload = vk_api.VkUpload(self.session)
        return upload.photo_messages(photo_path)
```

### 3. Message Processing Service

```python
# vk-service/app/services/message_service.py
import httpx
from app.models.vk_client import VKClient
from app.services.chatwoot_service import ChatwootService
import logging

class MessageService:
    def __init__(self):
        self.chatwoot = ChatwootService()
    
    async def process_vk_message(self, event):
        """Process incoming VK message and send to Chatwoot"""
        message_data = event.object.get('message', {})
        group_id = event.group_id
        
        # Get channel configuration from Chatwoot
        channel_config = await self.chatwoot.get_vk_channel(group_id)
        if not channel_config:
            logging.warning(f"No channel config found for VK group {group_id}")
            return
        
        # Create VK client
        vk_client = VKClient(channel_config['access_token'], group_id)
        
        # Get user information
        user_id = message_data.get('from_id')
        if user_id == group_id:  # Skip messages from the group itself
            return
            
        user_info = vk_client.get_user_info(user_id)
        
        # Prepare message for Chatwoot
        chatwoot_message = {
            'source_id': str(user_id),
            'content': message_data.get('text', ''),
            'message_type': 'incoming',
            'external_id': str(message_data.get('id')),
            'timestamp': message_data.get('date'),
            'contact': {
                'name': f"{user_info.get('first_name', '')} {user_info.get('last_name', '')}".strip() if user_info else f"VK User {user_id}",
                'avatar_url': user_info.get('photo_200') if user_info else None
            }
        }
        
        # Send to Chatwoot
        await self.chatwoot.create_message(channel_config['inbox_id'], chatwoot_message)
    
    async def send_to_vk(self, channel_config, recipient_id, content, attachments=None):
        """Send message from Chatwoot to VK"""
        vk_client = VKClient(channel_config['access_token'], channel_config['group_id'])
        
        try:
            message_id = vk_client.send_message(
                peer_id=int(recipient_id),
                message=content,
                attachments=attachments
            )
            return {'success': True, 'message_id': message_id}
        except Exception as e:
            return {'success': False, 'error': str(e)}
```

### 4. Chatwoot Service

```python
# vk-service/app/services/chatwoot_service.py
import httpx
import os
from typing import Dict, Optional

class ChatwootService:
    def __init__(self):
        self.base_url = os.getenv('CHATWOOT_URL', 'http://localhost:3000')
        self.api_key = os.getenv('CHATWOOT_API_KEY')
        self.headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {self.api_key}'
        }
    
    async def get_vk_channel(self, group_id: int) -> Optional[Dict]:
        """Get VK channel configuration from Chatwoot"""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{self.base_url}/api/v1/vk/channels/{group_id}",
                headers=self.headers
            )
            return response.json() if response.status_code == 200 else None
    
    async def create_message(self, inbox_id: int, message_data: Dict):
        """Create message in Chatwoot inbox"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/api/v1/inboxes/{inbox_id}/messages",
                json=message_data,
                headers=self.headers
            )
            return response.json() if response.status_code == 200 else None
    
    async def send_message(self, message_id: int, status: str, external_id: str = None):
        """Update message status in Chatwoot"""
        async with httpx.AsyncClient() as client:
            await client.patch(
                f"{self.base_url}/api/v1/messages/{message_id}",
                json={
                    'status': status,
                    'external_id': external_id
                },
                headers=self.headers
            )
```

## Database Schema

### VK Channel Table

```sql
-- Migration: db/migrate/add_vk_channel.rb
CREATE TABLE channel_vk (
    id BIGSERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL,
    access_token VARCHAR NOT NULL,
    group_id VARCHAR NOT NULL,
    group_name VARCHAR,
    confirmation_token VARCHAR,
    webhook_url VARCHAR,
    expires_at TIMESTAMP,
    authorization_error_count INTEGER DEFAULT 0,
    reauthorization_required BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    
    CONSTRAINT fk_channel_vk_account
        FOREIGN KEY (account_id) REFERENCES accounts(id)
        ON DELETE CASCADE,
    
    CONSTRAINT unique_vk_group_per_account
        UNIQUE (account_id, group_id)
);

CREATE INDEX idx_channel_vk_group_id ON channel_vk(group_id);
CREATE INDEX idx_channel_vk_account_id ON channel_vk(account_id);
```

### Rails Migration

```ruby
# db/migrate/20240101000000_add_vk_channel.rb
class AddVkChannel < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_vk do |t|
      t.integer :account_id, null: false
      t.string :access_token, null: false
      t.string :group_id, null: false
      t.string :group_name
      t.string :confirmation_token
      t.string :webhook_url
      t.datetime :expires_at
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
   - `offline` - Long-term access token

### OAuth Flow Implementation

```ruby
# app/controllers/concerns/vk_concern.rb
module VkConcern
  extend ActiveSupport::Concern

  def vk_oauth_client
    OAuth2::Client.new(
      vk_app_id,
      vk_app_secret,
      {
        site: 'https://oauth.vk.com',
        authorize_url: '/authorize',
        token_url: '/access_token'
      }
    )
  end

  def vk_authorization_url(state)
    vk_oauth_client.auth_code.authorize_url(
      redirect_uri: vk_callback_url,
      scope: 'messages,groups,offline',
      state: state,
      v: '5.131'
    )
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
    response = vk_api_client.groups.setCallbackSettings(
      group_id: channel.group_id,
      server_id: get_or_create_server_id,
      message_new: 1,
      message_reply: 1,
      message_edit: 1
    )

    Rails.logger.info("VK webhook configured: #{response}")
  end

  def remove
    servers = vk_api_client.groups.getCallbackServers(group_id: channel.group_id)
    
    servers['items'].each do |server|
      vk_api_client.groups.deleteCallbackServer(
        group_id: channel.group_id,
        server_id: server['id']
      )
    end
  end

  private

  def get_or_create_server_id
    servers = vk_api_client.groups.getCallbackServers(group_id: channel.group_id)
    
    existing_server = servers['items'].find { |s| s['url'] == webhook_url }
    return existing_server['id'] if existing_server

    response = vk_api_client.groups.addCallbackServer(
      group_id: channel.group_id,
      url: webhook_url,
      title: 'Chatwoot Integration',
      secret_key: webhook_secret_key
    )

    response['server_id']
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

  def vk_api_client
    @vk_api_client ||= VK::Application.new(
      app_id: GlobalConfigService.load('VK_APP_ID', ''),
      app_secret: GlobalConfigService.load('VK_APP_SECRET', ''),
      access_token: channel.access_token
    )
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
VK_CONFIRMATION_TOKEN=default_confirmation_token

# Chatwoot Configuration
FRONTEND_URL=https://your-chatwoot-instance.com
```

### Optional Configuration

```bash
# Feature Flags
ENABLE_VK_CHANNEL=true
VK_RATE_LIMIT_REQUESTS_PER_SECOND=20

# Python Microservice (if using)
VK_SERVICE_URL=http://vk-service:8000
CHATWOOT_API_KEY=your_api_key
```

### Global Configuration

```ruby
# Add to config/initializers/vk.rb
Rails.application.configure do
  config.vk = ActiveSupport::OrderedOptions.new
  config.vk.app_id = ENV['VK_APP_ID']
  config.vk.app_secret = ENV['VK_APP_SECRET']
  config.vk.api_version = ENV.fetch('VK_API_VERSION', '5.131')
  config.vk.webhook_secret = ENV['VK_WEBHOOK_SECRET']
end
```

## Security Considerations

### 1. Token Security
- Store access tokens encrypted in database
- Implement token rotation for long-lived tokens
- Use secure random generation for webhook secrets

### 2. Webhook Verification
```ruby
def verify_vk_signature(data, signature, secret_key)
  expected_signature = Digest::SHA256.hexdigest("#{data}#{secret_key}")
  ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
end
```

### 3. Rate Limiting
- Implement rate limiting for VK API calls (20 requests/second)
- Use Redis-based rate limiting
- Handle VK API rate limit responses gracefully

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
    it { should validate_uniqueness_of(:group_id).scoped_to(:account_id) }
  end

  describe 'callbacks' do
    it 'sets up webhook after creation' do
      expect(Vk::WebhookService).to receive_service_call.with(any_args)
      create(:channel_vk)
    end
  end
end
```

### 2. Integration Tests

```ruby
# spec/controllers/webhooks/vk_controller_spec.rb
RSpec.describe Webhooks::VkController do
  describe 'POST #events' do
    context 'with confirmation event' do
      it 'returns confirmation token' do
        post :events, params: { type: 'confirmation', group_id: 12345 }
        expect(response.body).to eq('confirmation_token')
      end
    end

    context 'with message_new event' do
      it 'queues VK events job' do
        expect(Webhooks::VkEventsJob).to receive(:perform_later)
        post :events, params: vk_message_params
      end
    end
  end
end
```

### 3. VK API Mock

```ruby
# spec/support/vk_api_mock.rb
class VkApiMock
  def self.setup
    WebMock.stub_request(:post, /api\.vk\.com/)
      .to_return(status: 200, body: { response: {} }.to_json)
  end
end
```

## Deployment Guide

### 1. Ruby Implementation Deployment

```bash
# Add VK gem to Gemfile
echo 'gem "vk-ruby"' >> Gemfile
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

### 2. Python Microservice Deployment

```dockerfile
# vk-service/Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```yaml
# docker-compose.yml addition
services:
  vk-service:
    build: ./vk-service
    ports:
      - "8000:8000"
    environment:
      - CHATWOOT_URL=http://chatwoot:3000
      - CHATWOOT_API_KEY=${CHATWOOT_API_KEY}
      - VK_APP_ID=${VK_APP_ID}
      - VK_APP_SECRET=${VK_APP_SECRET}
    depends_on:
      - chatwoot
```

### 3. Routes Configuration

```ruby
# config/routes.rb additions
Rails.application.routes.draw do
  # VK webhook routes
  get 'webhooks/vk', to: 'webhooks/vk#verify'
  post 'webhooks/vk', to: 'webhooks/vk#events'
  
  # VK OAuth callback
  get 'vk/callback', to: 'vk/callbacks#show'
  
  # VK API routes (for Python service integration)
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :vk_channels, only: [:show, :create, :update, :destroy]
      post 'vk/send_message', to: 'vk#send_message'
    end
  end
end
```

### 4. Monitoring & Logging

```ruby
# Add to application.rb
config.log_tags = [:request_id, :remote_ip]

# VK-specific logging
Rails.logger.tagged('VK') do |logger|
  logger.info 'VK webhook received'
end
```

### 5. Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def vk
    # Check VK API connectivity
    vk_client = VK::Application.new(token: 'test_token')
    
    begin
      vk_client.users.get(user_ids: 1)
      render json: { status: 'healthy', service: 'vk' }
    rescue StandardError => e
      render json: { status: 'unhealthy', service: 'vk', error: e.message }, status: 503
    end
  end
end
```

## Conclusion

This technical solution provides comprehensive guidance for integrating VK.com into Chatwoot's inbox system. The Ruby implementation is recommended for consistency with Chatwoot's architecture, while the Python microservice approach offers flexibility for teams preferring Python's mature VK ecosystem.

Key implementation considerations:
- Follow Chatwoot's established channel patterns
- Implement robust error handling and rate limiting
- Ensure secure token management and webhook verification
- Provide comprehensive testing coverage
- Plan for scalable deployment and monitoring

The solution supports both VK Communities (recommended) and personal messaging, with proper OAuth flow, webhook handling, and message synchronization between VK and Chatwoot platforms.