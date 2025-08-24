class SuperAdmin::AppConfigsController < SuperAdmin::ApplicationController
  before_action :fetch_app_config, only: [:show, :update]

  def show; end

  def create
    @app_config = InstallationConfig.new(app_config_params)
    @app_config.locked = true

    if @app_config.save
      redirect_to super_admin_app_config_path(@app_config)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @app_config.update(app_config_params)
      redirect_to super_admin_app_config_path(@app_config)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def fetch_app_config
    @app_config = InstallationConfig.find(params[:id])
  end

  def app_config_params
    params.require(:installation_config).permit(
      :name,
      serialized_value: [
        :LOGO, :LOGO_THUMBNAIL, :INSTALLATION_NAME,
        :WIDGET_BRAND_URL, :TERMS_URL, :PRIVACY_URL, :BRAND_URL,
        :FACEBOOK_APP_ID, :FACEBOOK_API_VERSION, :FACEBOOK_APP_SECRET, :FACEBOOK_VERIFY_TOKEN,
        :GOOGLE_OAUTH_CLIENT_ID, :GOOGLE_OAUTH_CLIENT_SECRET,
        :TWITTER_APP_ID, :TWITTER_CONSUMER_KEY, :TWITTER_CONSUMER_SECRET,
        :SLACK_CLIENT_ID, :SLACK_CLIENT_SECRET,
        :INSTAGRAM_APP_ID, :INSTAGRAM_APP_SECRET, :INSTAGRAM_VERIFY_TOKEN,
        :VK_APP_ID, :VK_APP_SECRET, :VK_VERIFY_TOKEN, :VK_WEBHOOK_SECRET, :VK_API_VERSION,
        :AZURE_APP_ID, :AZURE_APP_SECRET,
        :OPENAI_API_KEY,
        :CW_SUPPORT_EMAIL, :CW_SUPPORT_IDENTITY_NAME, :CW_SUPPORT_IDENTITY_EMAIL
      ]
    )
  end
end