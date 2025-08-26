class Vk::WebhookService < Vk::BaseService
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
      title: 'Chatwoot',
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

  def webhook_url
    Rails.application.routes.url_helpers.webhooks_vk_url(
      protocol: Rails.application.config.force_ssl ? 'https' : 'https',
      host: ENV.fetch('FRONTEND_URL', 'localhost:3000').gsub(/https?:\/\//, '')
    )
  end

  def webhook_secret_key
    GlobalConfigService.load('VK_WEBHOOK_SECRET', '')
  end
end
