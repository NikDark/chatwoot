<script>
import SimpleDivider from '../Divider/SimpleDivider.vue';

export default {
  components: {
    SimpleDivider,
  },
  props: {
    showSeparator: {
      type: Boolean,
      default: true,
    },
  },
  methods: {
    async handleVkLogin() {
      const authUrl = await this.getVkAuthUrl();
      window.location.href = authUrl;
    },
    
    async getVkAuthUrl() {
      // VK ID OAuth 2.1 authorization URL according to the new documentation
      const baseUrl = 'https://id.vk.com/authorize';
      const clientId = window.chatwootConfig.vkIdClientId;
      const redirectUri = window.chatwootConfig.vkIdCallbackUrl;
      const responseType = 'code';
      const scope = 'email';
      
      // Generate PKCE parameters for security
      const codeVerifier = this.generateCodeVerifier();
      const codeChallenge = await this.generateCodeChallenge(codeVerifier);
      const state = this.generateState();
      
      // Store code_verifier and state in sessionStorage for later use
      sessionStorage.setItem('vk_code_verifier', codeVerifier);
      sessionStorage.setItem('vk_state', state);

      // Build the query string according to VK ID OAuth 2.1 specification
      const queryString = new URLSearchParams({
        client_id: clientId,
        redirect_uri: redirectUri,
        response_type: responseType,
        scope: scope,
        code_challenge: codeChallenge,
        code_challenge_method: 'S256',
        state: state,
      }).toString();

      // Construct the full URL
      return `${baseUrl}?${queryString}`;
    },
    
    // Generate code_verifier for PKCE
    generateCodeVerifier() {
      const array = new Uint8Array(32);
      crypto.getRandomValues(array);
      return btoa(String.fromCharCode.apply(null, array))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '')
        .substr(0, 43);
    },
    
    // Generate code_challenge from code_verifier
    async generateCodeChallenge(codeVerifier) {
      const encoder = new TextEncoder();
      const data = encoder.encode(codeVerifier);
      const digest = await crypto.subtle.digest('SHA-256', data);
      return btoa(String.fromCharCode.apply(null, new Uint8Array(digest)))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
    },
    
    // Generate state parameter for CSRF protection
    generateState() {
      const array = new Uint8Array(16);
      crypto.getRandomValues(array);
      return btoa(String.fromCharCode.apply(null, array))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
    },
  },
};
</script>

<!-- eslint-disable vue/no-unused-refs -->
<!-- Added ref for writing specs -->
<template>
  <div class="flex flex-col">
    <button
      @click="handleVkLogin"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
    >
      <!-- VK ID logo/icon -->
      <svg width="24" height="24" viewBox="0 0 24 24" class="h-6">
        <path 
          fill="#0077FF" 
          d="M12.785 16.241s.288-.032.436-.193c.136-.148.131-.426.131-.426s-.019-1.302.58-1.494c.59-.189 1.348 1.258 2.151 1.815.607.421 1.068.329 1.068.329l2.141-.03s1.119-.069.589-.956c-.043-.072-.309-.657-1.595-1.858-1.348-1.257-1.168-1.054.456-3.229.988-1.323 1.382-2.131 1.259-2.478-.118-.33-.842-.243-.842-.243l-2.408.015s-.178-.025-.31.055c-.127.076-.209.254-.209.254s-.375 1.008-.875 1.864c-1.056 1.805-1.478 1.9-1.651 1.789-.402-.259-.302-1.041-.302-1.598 0-1.736.261-2.46-.51-2.647-.256-.062-.444-.103-1.098-.11-.84-.009-1.551.003-1.954.201-.268.132-.475.425-.349.442.156.021.509.096.696.352.241.331.232.939.232.939s.138 2.045-.322 2.3c-.316.175-.75-.182-1.681-1.816-.477-.835-.837-1.759-.837-1.759s-.069-.171-.193-.263c-.15-.112-.361-.147-.361-.147l-2.286.015s-.344.01-.469.159c-.111.133-.009.408-.009.408s1.76 4.158 3.754 6.256c1.832 1.927 3.911 1.8 3.911 1.8z"
        />
      </svg>
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.OAUTH.VK_LOGIN') }}
      </span>
    </button>
    <SimpleDivider
      v-if="showSeparator"
      ref="divider"
      :label="$t('COMMON.OR')"
      class="uppercase"
    />
  </div>
</template>