require 'omniauth-oauth2'
require 'digest'
require 'base64'

module OmniAuth
  module Strategies
    class VkId < OmniAuth::Strategies::OAuth2
      # Give your strategy a name.
      option :name, 'vk_id'

      # This is where you pass the options you would pass when
      # initializing your consumer from the OAuth gem.
      option :client_options, {
        site: 'https://id.vk.com',
        authorize_url: '/authorize',
        token_url: '/oauth2/auth'
      }

      # These are called after authentication has succeeded. If
      # possible, you should try to set the UID without making
      # additional calls (if the user id is returned with the token
      # or as a URI parameter). This may not be possible with all
      # providers.
      uid { raw_info['user']['user_id'] }

      info do
        {
          email: raw_info['user']['email'],
          first_name: raw_info['user']['first_name'],
          last_name: raw_info['user']['last_name'],
          name: "#{raw_info['user']['first_name']} #{raw_info['user']['last_name']}".strip,
          avatar: raw_info['user']['avatar']
        }
      end

      extra do
        {
          'raw_info' => raw_info,
          'access_token' => access_token.token,
          'refresh_token' => access_token.refresh_token,
          'id_token' => access_token.params['id_token']
        }
      end

      # Override authorize_params to include PKCE parameters
      def authorize_params
        super.tap do |params|
          # Generate PKCE parameters
          @code_verifier = generate_code_verifier
          @code_challenge = generate_code_challenge(@code_verifier)
          
          params[:code_challenge] = @code_challenge
          params[:code_challenge_method] = 'S256'
          params[:response_type] = 'code'
          
          # Add state parameter for CSRF protection
          params[:state] = SecureRandom.hex(16) unless params[:state]
          
          # Store code_verifier in session for token exchange
          session['omniauth.vk_id.code_verifier'] = @code_verifier
          session['omniauth.vk_id.state'] = params[:state]
        end
      end

      # Override token_params to include PKCE code_verifier
      def token_params
        super.tap do |params|
          params[:grant_type] = 'authorization_code'
          params[:code_verifier] = session.delete('omniauth.vk_id.code_verifier')
          params[:redirect_uri] = callback_url
        end
      end

      # Validate state parameter
      def callback_phase
        # Verify state parameter
        if request.params['state'] != session.delete('omniauth.vk_id.state')
          fail!(:csrf_detected, CallbackError.new(:csrf_detected, "CSRF detected"))
          return
        end
        
        super
      rescue ::OAuth2::Error => e
        fail!(:invalid_credentials, e)
      rescue ::Timeout::Error => e
        fail!(:timeout, e)
      rescue ::Errno::ECONNREFUSED => e
        fail!(:service_unavailable, e)
      end

      def raw_info
        @raw_info ||= access_token.get('/oauth2/user_info').parsed
      end

      private

      # Generate code_verifier for PKCE
      def generate_code_verifier
        SecureRandom.urlsafe_base64(32).tr('+/=', '-_')[0, 43]
      end

      # Generate code_challenge from code_verifier
      def generate_code_challenge(code_verifier)
        digest = Digest::SHA256.digest(code_verifier)
        Base64.urlsafe_encode64(digest).tr('+/=', '-_')[0, 43]
      end
    end
  end
end