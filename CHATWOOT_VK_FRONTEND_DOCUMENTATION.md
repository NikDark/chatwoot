# Chatwoot VK.com Frontend Integration Documentation

## Overview

This document provides comprehensive frontend implementation guidelines for integrating VK.com into Chatwoot's inbox system. The implementation follows Chatwoot's established patterns for social media integrations like Facebook and Instagram.

## Table of Contents

1. [Frontend Architecture Overview](#frontend-architecture-overview)
2. [Required Frontend Files](#required-frontend-files)
3. [Vue Components Implementation](#vue-components-implementation)
4. [API Client Implementation](#api-client-implementation)
5. [Store/State Management](#storestate-management)
6. [Internationalization (i18n)](#internationalization-i18n)
7. [Routing Configuration](#routing-configuration)
8. [UI/UX Components](#uiux-components)
9. [Testing Implementation](#testing-implementation)
10. [Build and Deployment](#build-and-deployment)

## Frontend Architecture Overview

The VK integration follows Chatwoot's channel pattern with these key components:

- **Channel Setup Component** - VK OAuth authorization flow
- **API Client** - VK-specific API calls
- **Store Module** - VK channel state management
- **Internationalization** - Multi-language support
- **Routing** - VK-specific routes and navigation

### File Structure

```
app/javascript/dashboard/
├── routes/dashboard/settings/inbox/channels/
│   └── Vk.vue                           # VK channel setup component
├── api/channel/
│   └── vkClient.js                      # VK API client
├── store/modules/
│   └── inboxes.js                       # Updated with VK actions
├── i18n/locale/en/
│   └── inboxMgmt.json                   # Updated with VK translations
└── components/widgets/
    └── ChannelItem.vue                  # Updated to include VK
```

## Required Frontend Files

### 1. VK Channel Setup Component

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Vk.vue`

```vue
<script>
import { useVuelidate } from '@vuelidate/core';
import { useAccount } from 'dashboard/composables/useAccount';
import vkClient from 'dashboard/api/channel/vkClient';

export default {
  setup() {
    const { accountId } = useAccount();
    return {
      accountId,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      isCreating: false,
      hasError: false,
      errorStateMessage: '',
      errorStateDescription: '',
      isRequestingAuthorization: false,
    };
  },

  mounted() {
    const urlParams = new URLSearchParams(window.location.search);
    const errorCode = urlParams.get('code');
    const errorMessage = urlParams.get('error_message');

    if (errorMessage) {
      this.hasError = true;
      if (errorCode === '400') {
        this.errorStateMessage = errorMessage;
        this.errorStateDescription = this.$t(
          'INBOX_MGMT.ADD.VK.ERROR_AUTH'
        );
      } else {
        this.errorStateMessage = this.$t(
          'INBOX_MGMT.ADD.VK.ERROR_MESSAGE'
        );
        this.errorStateDescription = errorMessage;
      }
    }
    
    // Clean URL to allow retry
    const cleanURL = window.location.pathname;
    window.history.replaceState({}, document.title, cleanURL);
  },

  methods: {
    async requestAuthorization() {
      this.isRequestingAuthorization = true;
      try {
        const response = await vkClient.generateAuthorization({
          account_id: this.accountId
        });
        const { data: { url } } = response;
        window.location.href = url;
      } catch (error) {
        this.hasError = true;
        this.errorStateMessage = this.$t('INBOX_MGMT.ADD.VK.ERROR_MESSAGE');
        this.isRequestingAuthorization = false;
      }
    },
  },
};
</script>

<template>
  <div
    class="border border-n-weak bg-n-background h-full p-6 w-full max-w-full md:w-3/4 md:max-w-[75%] flex-shrink-0 flex-grow-0"
  >
    <div class="flex flex-col items-center justify-start h-full text-center">
      <div v-if="hasError" class="max-w-lg mx-auto text-center">
        <h5>{{ errorStateMessage }}</h5>
        <p
          v-if="errorStateDescription"
          v-dompurify-html="errorStateDescription"
        />
      </div>
      <div
        v-else
        class="flex flex-col items-center justify-center px-8 py-10 text-center shadow rounded-3xl outline outline-1 outline-n-weak"
      >
        <h6 class="text-2xl font-medium">
          {{ $t('INBOX_MGMT.ADD.VK.CONNECT_YOUR_VK_COMMUNITY') }}
        </h6>
        <p class="py-6 text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.VK.HELP') }}
        </p>
        <button
          class="flex items-center justify-center px-8 py-3.5 gap-2 text-white rounded-full bg-gradient-to-r from-[#4C75A3] to-[#5B7DB1] hover:shadow-lg transition-all duration-300 min-w-[240px] overflow-hidden"
          :disabled="isRequestingAuthorization"
          @click="requestAuthorization()"
        >
          <span class="i-ri-user-line size-5" />
          <span class="text-base font-medium">
            {{ $t('INBOX_MGMT.ADD.VK.CONTINUE_WITH_VK') }}
          </span>
          <span v-if="isRequestingAuthorization" class="ml-2">
            <svg
              class="w-5 h-5 animate-spin"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
          </span>
        </button>
      </div>
    </div>
  </div>
</template>
```

### 2. VK API Client

**File:** `app/javascript/dashboard/api/channel/vkClient.js`

```javascript
/* global axios */
import ApiClient from '../ApiClient';

class VkChannel extends ApiClient {
  constructor() {
    super('vk', { accountScoped: true });
  }

  generateAuthorization(payload) {
    return axios.post(`${this.url}/authorization`, payload);
  }

  getChannels() {
    return axios.get(`${this.url}/channels`);
  }

  createChannel(payload) {
    return axios.post(`${this.url}/channels`, payload);
  }

  updateChannel(channelId, payload) {
    return axios.patch(`${this.url}/channels/${channelId}`, payload);
  }

  deleteChannel(channelId) {
    return axios.delete(`${this.url}/channels/${channelId}`);
  }

  reauthorizeChannel(channelId) {
    return axios.post(`${this.url}/channels/${channelId}/reauthorize`);
  }
}

export default new VkChannel();
```

### 3. Store Module Updates

**File:** `app/javascript/dashboard/store/modules/inboxes.js` (Updates)

```javascript
// Add VK-specific actions to the existing inboxes store module

// In the actions object, add:
async createVkChannel({ commit }, params) {
  try {
    const response = await VkAPI.createChannel(params);
    commit(types.SET_INBOX_CREATION_STATUS, { isCreating: false, isCreated: true });
    return response.data;
  } catch (error) {
    commit(types.SET_INBOX_CREATION_STATUS, { isCreating: false, isCreated: false });
    throw new Error(error);
  }
},

async reauthorizeVkChannel({ commit }, { channelId, params }) {
  try {
    const response = await VkAPI.reauthorizeChannel(channelId, params);
    return response.data;
  } catch (error) {
    throw new Error(error);
  }
},
```

### 4. Channel List Updates

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue` (Updates)

```javascript
// In the channelList computed property, add VK:
channelList() {
  const { apiChannelName, apiChannelThumbnail } = this.globalConfig;
  return [
    { key: 'website', name: 'Website' },
    { key: 'facebook', name: 'Messenger' },
    { key: 'whatsapp', name: 'WhatsApp' },
    { key: 'sms', name: 'SMS' },
    { key: 'email', name: 'Email' },
    {
      key: 'api',
      name: apiChannelName || 'API',
      thumbnail: apiChannelThumbnail,
    },
    { key: 'telegram', name: 'Telegram' },
    { key: 'line', name: 'Line' },
    { key: 'instagram', name: 'Instagram' },
    { key: 'vk', name: 'VK' }, // Add VK here
    { key: 'voice', name: 'Voice' },
  ];
},
```

## API Client Implementation

### VK Authorization Flow

The VK authorization follows OAuth 2.0 pattern similar to Instagram:

```javascript
// app/javascript/dashboard/api/channel/vkClient.js
class VkChannel extends ApiClient {
  async generateAuthorization(payload = {}) {
    try {
      const response = await axios.post(`${this.url}/authorization`, {
        account_id: payload.account_id,
        ...payload
      });
      return response;
    } catch (error) {
      throw new Error(error.response?.data?.message || 'Authorization failed');
    }
  }

  async handleCallback(code, state) {
    try {
      const response = await axios.post(`${this.url}/callback`, {
        code,
        state
      });
      return response;
    } catch (error) {
      throw new Error(error.response?.data?.message || 'Callback handling failed');
    }
  }
}
```

## Store/State Management

### Inbox Store Updates

Add VK-specific actions and mutations to the existing inbox store:

```javascript
// In store/modules/inboxes.js

// Actions
const actions = {
  // ... existing actions

  async createVkChannel({ commit, dispatch }, params) {
    commit(types.SET_INBOX_CREATION_STATUS, { isCreating: true });
    try {
      const response = await VkAPI.createChannel(params);
      const data = response.data.payload;
      
      commit(types.ADD_INBOX, data);
      commit(types.SET_INBOX_CREATION_STATUS, { 
        isCreating: false, 
        isCreated: true 
      });
      
      return data;
    } catch (error) {
      commit(types.SET_INBOX_CREATION_STATUS, { 
        isCreating: false, 
        isCreated: false 
      });
      throw new Error(error);
    }
  },

  async reauthorizeVkChannel({ commit }, { inboxId, channelId }) {
    try {
      const response = await VkAPI.reauthorizeChannel(channelId);
      
      // Update inbox status
      commit(types.UPDATE_INBOX, {
        id: inboxId,
        reauthorization_required: false
      });
      
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  }
};
```

## Internationalization (i18n)

### English Translations

**File:** `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` (Add VK section)

```json
{
  "INBOX_MGMT": {
    "ADD": {
      "VK": {
        "CONTINUE_WITH_VK": "Continue with VK",
        "CONNECT_YOUR_VK_COMMUNITY": "Connect your VK Community",
        "HELP": "To add your VK community as a channel, you need to authenticate by clicking 'Continue with VK'. This will allow you to receive and respond to messages from your VK community.",
        "ERROR_MESSAGE": "There was an error connecting to VK, please try again",
        "ERROR_AUTH": "Authentication failed. Please ensure your VK application is properly configured and try again.",
        "CHOOSE_COMMUNITY": "Choose Community",
        "CHOOSE_PLACEHOLDER": "Select a community from the list",
        "INBOX_NAME": "Inbox Name",
        "ADD_NAME": "Add a name for your inbox",
        "PICK_NAME": "Pick a Name for your Inbox",
        "PICK_A_VALUE": "Pick a value",
        "CREATE_INBOX": "Create Inbox",
        "LOADING_COMMUNITIES": "Loading VK communities...",
        "NO_COMMUNITIES": "No VK communities found. Please ensure you have admin access to at least one VK community.",
        "COMMUNITY_SELECTION_ERROR": "Please select a community to continue",
        "REAUTHORIZATION_REQUIRED": "Your VK integration needs reauthorization. Click to reconnect.",
        "REAUTHORIZATION_SUCCESS": "VK integration successfully reauthorized",
        "REAUTHORIZATION_ERROR": "Failed to reauthorize VK integration"
      }
    },
    "DETAILS": {
      "VK": {
        "TITLE": "VK Community Settings",
        "DESC": "Configure your VK community integration settings",
        "COMMUNITY_NAME": "Community Name",
        "COMMUNITY_ID": "Community ID",
        "WEBHOOK_URL": "Webhook URL",
        "CONFIRMATION_TOKEN": "Confirmation Token",
        "ACCESS_TOKEN_STATUS": "Access Token Status",
        "LAST_SYNC": "Last Synchronization",
        "REAUTHORIZE": "Reauthorize",
        "DISCONNECT": "Disconnect"
      }
    }
  }
}
```

### Russian Translations

**File:** `app/javascript/dashboard/i18n/locale/ru/inboxMgmt.json` (Add VK section)

```json
{
  "INBOX_MGMT": {
    "ADD": {
      "VK": {
        "CONTINUE_WITH_VK": "Продолжить с ВК",
        "CONNECT_YOUR_VK_COMMUNITY": "Подключите ваше сообщество ВК",
        "HELP": "Чтобы добавить ваше сообщество ВК как канал, необходимо авторизоваться, нажав 'Продолжить с ВК'. Это позволит получать и отвечать на сообщения из вашего сообщества ВК.",
        "ERROR_MESSAGE": "Произошла ошибка подключения к ВК, попробуйте снова",
        "ERROR_AUTH": "Ошибка авторизации. Убедитесь, что ваше приложение ВК настроено правильно и попробуйте снова.",
        "CHOOSE_COMMUNITY": "Выберите сообщество",
        "CHOOSE_PLACEHOLDER": "Выберите сообщество из списка",
        "INBOX_NAME": "Название входящих",
        "ADD_NAME": "Добавьте название для ваших входящих",
        "PICK_NAME": "Выберите название для ваших входящих",
        "PICK_A_VALUE": "Выберите значение",
        "CREATE_INBOX": "Создать входящие",
        "LOADING_COMMUNITIES": "Загрузка сообществ ВК...",
        "NO_COMMUNITIES": "Сообщества ВК не найдены. Убедитесь, что у вас есть права администратора хотя бы в одном сообществе ВК.",
        "COMMUNITY_SELECTION_ERROR": "Пожалуйста, выберите сообщество для продолжения",
        "REAUTHORIZATION_REQUIRED": "Ваша интеграция с ВК требует повторной авторизации. Нажмите для переподключения.",
        "REAUTHORIZATION_SUCCESS": "Интеграция с ВК успешно переавторизована",
        "REAUTHORIZATION_ERROR": "Не удалось переавторизовать интеграцию с ВК"
      }
    }
  }
}
```

## Routing Configuration

### Route Updates

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/routes.js` (Updates)

```javascript
// Add VK route to the channel routes
const routes = [
  // ... existing routes
  {
    path: 'vk',
    name: 'settings_inboxes_page_channel_vk',
    component: () => import('./channels/Vk.vue'),
    props: true,
  },
];
```

### Channel Factory Updates

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelFactory.vue` (Updates)

```javascript
// In the component mapping, add VK:
computed: {
  channelComponent() {
    const channelMap = {
      website: 'Website',
      facebook: 'Facebook', 
      whatsapp: 'Whatsapp',
      sms: 'Sms',
      email: 'Email',
      api: 'Api',
      telegram: 'Telegram',
      line: 'Line',
      instagram: 'Instagram',
      vk: 'Vk', // Add VK mapping
      voice: 'Voice',
    };
    
    return channelMap[this.channelName] || null;
  }
}
```

## UI/UX Components

### VK Reauthorization Component

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/vk/Reauthorize.vue`

```vue
<script>
import { useAlert } from 'dashboard/composables';
import vkClient from 'dashboard/api/channel/vkClient';

export default {
  props: {
    inboxId: {
      type: [String, Number],
      required: true,
    },
    channelId: {
      type: [String, Number], 
      required: true,
    }
  },
  data() {
    return {
      isReauthorizing: false,
    };
  },
  methods: {
    async reauthorize() {
      this.isReauthorizing = true;
      try {
        await this.$store.dispatch('inboxes/reauthorizeVkChannel', {
          inboxId: this.inboxId,
          channelId: this.channelId
        });
        
        useAlert(this.$t('INBOX_MGMT.ADD.VK.REAUTHORIZATION_SUCCESS'));
        this.$router.push({ 
          name: 'settings_inbox_show', 
          params: { inboxId: this.inboxId } 
        });
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.ADD.VK.REAUTHORIZATION_ERROR'));
      } finally {
        this.isReauthorizing = false;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col items-center justify-center p-8">
    <div class="mb-6">
      <i class="text-6xl text-orange-400 ri-error-warning-line" />
    </div>
    <h3 class="mb-4 text-xl font-medium text-center">
      {{ $t('INBOX_MGMT.ADD.VK.REAUTHORIZATION_REQUIRED') }}
    </h3>
    <button
      class="px-6 py-3 text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50"
      :disabled="isReauthorizing"
      @click="reauthorize"
    >
      <span v-if="isReauthorizing" class="mr-2">
        <i class="animate-spin ri-loader-4-line" />
      </span>
      {{ $t('INBOX_MGMT.DETAILS.VK.REAUTHORIZE') }}
    </button>
  </div>
</template>
```

### VK Channel Icon

**File:** `app/javascript/shared/components/FluentIcon/dashboard-icons.json` (Add VK icon)

```json
{
  "vk": {
    "name": "vk",
    "icon": "ri-user-line",
    "color": "#4C75A3"
  }
}
```

## Testing Implementation

### Unit Tests for VK Component

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/specs/Vk.spec.js`

```javascript
import { mount } from '@vue/test-utils';
import Vk from '../Vk.vue';
import vkClient from 'dashboard/api/channel/vkClient';

// Mock the VK client
jest.mock('dashboard/api/channel/vkClient');

describe('Vk.vue', () => {
  let wrapper;

  beforeEach(() => {
    wrapper = mount(Vk, {
      global: {
        mocks: {
          $t: key => key,
          $store: {
            getters: {
              getCurrentAccountId: 1
            }
          }
        }
      }
    });
  });

  afterEach(() => {
    wrapper.unmount();
  });

  describe('Authorization Request', () => {
    it('should call vkClient.generateAuthorization when requestAuthorization is called', async () => {
      const mockResponse = { data: { url: 'https://oauth.vk.com/authorize?...' } };
      vkClient.generateAuthorization.mockResolvedValue(mockResponse);

      // Mock window.location.href
      delete window.location;
      window.location = { href: '' };

      await wrapper.vm.requestAuthorization();

      expect(vkClient.generateAuthorization).toHaveBeenCalledWith({
        account_id: 1
      });
      expect(window.location.href).toBe(mockResponse.data.url);
    });

    it('should handle authorization errors gracefully', async () => {
      const mockError = new Error('Authorization failed');
      vkClient.generateAuthorization.mockRejectedValue(mockError);

      await wrapper.vm.requestAuthorization();

      expect(wrapper.vm.hasError).toBe(true);
      expect(wrapper.vm.errorStateMessage).toBe('INBOX_MGMT.ADD.VK.ERROR_MESSAGE');
      expect(wrapper.vm.isRequestingAuthorization).toBe(false);
    });
  });

  describe('Error Handling', () => {
    it('should display error message when error params are present in URL', async () => {
      // Mock URL search params
      delete window.location;
      window.location = {
        search: '?error_message=Access denied&code=400',
        pathname: '/test'
      };

      // Mock history API
      window.history = {
        replaceState: jest.fn()
      };

      const errorWrapper = mount(Vk, {
        global: {
          mocks: {
            $t: key => key
          }
        }
      });

      expect(errorWrapper.vm.hasError).toBe(true);
      expect(errorWrapper.vm.errorStateMessage).toBe('Access denied');
      expect(window.history.replaceState).toHaveBeenCalled();
    });
  });

  describe('UI Rendering', () => {
    it('should render authorization button when no error', () => {
      const button = wrapper.find('button');
      expect(button.exists()).toBe(true);
      expect(button.text()).toContain('INBOX_MGMT.ADD.VK.CONTINUE_WITH_VK');
    });

    it('should render error message when hasError is true', async () => {
      await wrapper.setData({
        hasError: true,
        errorStateMessage: 'Test error message'
      });

      const errorDiv = wrapper.find('.max-w-lg');
      expect(errorDiv.exists()).toBe(true);
      expect(errorDiv.text()).toContain('Test error message');
    });

    it('should disable button when requesting authorization', async () => {
      await wrapper.setData({ isRequestingAuthorization: true });

      const button = wrapper.find('button');
      expect(button.attributes('disabled')).toBeDefined();
    });
  });
});
```

### API Client Tests

**File:** `app/javascript/dashboard/api/channel/specs/vkClient.spec.js`

```javascript
import vkClient from '../vkClient';
import ApiClient from '../../ApiClient';

describe('#VkClient', () => {
  it('creates correct instance', () => {
    expect(vkClient).toBeInstanceOf(ApiClient);
    expect(vkClient).toHaveProperty('generateAuthorization');
    expect(vkClient).toHaveProperty('createChannel');
    expect(vkClient).toHaveProperty('reauthorizeChannel');
  });

  describe('API methods', () => {
    beforeEach(() => {
      jest.clearAllMocks();
    });

    describe('#generateAuthorization', () => {
      it('should make POST request to authorization endpoint', async () => {
        const payload = { account_id: 1 };
        
        await vkClient.generateAuthorization(payload);
        
        expect(axios.post).toHaveBeenCalledWith(
          `${vkClient.url}/authorization`,
          payload
        );
      });
    });

    describe('#createChannel', () => {
      it('should make POST request to channels endpoint', async () => {
        const payload = { 
          group_id: '12345',
          access_token: 'token',
          inbox_name: 'Test VK Inbox'
        };
        
        await vkClient.createChannel(payload);
        
        expect(axios.post).toHaveBeenCalledWith(
          `${vkClient.url}/channels`,
          payload
        );
      });
    });

    describe('#reauthorizeChannel', () => {
      it('should make POST request to reauthorize endpoint', async () => {
        const channelId = 123;
        
        await vkClient.reauthorizeChannel(channelId);
        
        expect(axios.post).toHaveBeenCalledWith(
          `${vkClient.url}/channels/${channelId}/reauthorize`
        );
      });
    });
  });
});
```

## Build and Deployment

### Asset Pipeline Integration

Ensure VK assets are properly included in the build process:

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/index.js`

```javascript
// Add VK to the channel exports
export { default as Vk } from './Vk.vue';
```

### Environment Configuration

Add VK-specific configuration to the frontend config:

**File:** `app/controllers/dashboard_controller.rb` (Backend - for frontend config)

```ruby
def app_config
  {
    # ... existing config
    VK_APP_ID: GlobalConfigService.load('VK_APP_ID', ''),
    VK_API_VERSION: GlobalConfigService.load('VK_API_VERSION', '5.131'),
  }
end
```

### Webpack Configuration

Ensure VK components are properly chunked:

**File:** `config/webpack/environment.js` (if needed)

```javascript
// Add VK-specific chunk splitting if necessary
const { environment } = require('@rails/webpacker');

environment.splitChunks((config) => {
  config.cacheGroups.vkChannel = {
    name: 'vk-channel',
    chunks: 'all',
    test: /[\\/]channels[\\/]Vk\.vue$/,
  };
  return config;
});
```

## Feature Flags and Conditional Rendering

### Feature Flag Support

**File:** `app/javascript/dashboard/featureFlags.js` (Add VK feature flag)

```javascript
export const FEATURE_FLAGS = {
  // ... existing flags
  VK_INTEGRATION: 'vk_integration',
};
```

### Conditional Channel Display

**File:** `app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue` (Update with feature flag)

```javascript
computed: {
  channelList() {
    const channels = [
      { key: 'website', name: 'Website' },
      { key: 'facebook', name: 'Messenger' },
      // ... other channels
    ];

    // Add VK only if feature is enabled
    if (this.account.features?.vk_integration) {
      channels.push({ key: 'vk', name: 'VK' });
    }

    return channels;
  }
}
```

## Error Handling and User Experience

### Error Boundary Component

**File:** `app/javascript/dashboard/components/ErrorBoundary.vue`

```vue
<script>
export default {
  name: 'ErrorBoundary',
  data() {
    return {
      hasError: false,
      error: null,
    };
  },
  errorCaptured(error, instance, info) {
    this.hasError = true;
    this.error = error;
    
    // Log to error reporting service
    console.error('VK Integration Error:', error, info);
    
    return false;
  },
  methods: {
    retry() {
      this.hasError = false;
      this.error = null;
      this.$forceUpdate();
    },
  },
};
</script>

<template>
  <div v-if="hasError" class="error-boundary">
    <h3>Something went wrong with VK integration</h3>
    <p>{{ error?.message }}</p>
    <button @click="retry">Try Again</button>
  </div>
  <slot v-else />
</template>
```

### Loading States

Implement consistent loading states across VK components:

```vue
<template>
  <div class="vk-loading-state">
    <div v-if="isLoading" class="flex items-center justify-center p-8">
      <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      <span class="ml-3">{{ loadingMessage }}</span>
    </div>
    <slot v-else />
  </div>
</template>
```

## Accessibility and SEO

### Accessibility Features

Ensure VK integration is accessible:

```vue
<template>
  <div>
    <!-- Proper ARIA labels -->
    <button
      :aria-label="$t('INBOX_MGMT.ADD.VK.CONTINUE_WITH_VK')"
      :aria-describedby="isRequestingAuthorization ? 'vk-loading-desc' : 'vk-help-desc'"
      @click="requestAuthorization()"
    >
      {{ $t('INBOX_MGMT.ADD.VK.CONTINUE_WITH_VK') }}
    </button>
    
    <!-- Screen reader descriptions -->
    <div id="vk-help-desc" class="sr-only">
      {{ $t('INBOX_MGMT.ADD.VK.HELP') }}
    </div>
    <div v-if="isRequestingAuthorization" id="vk-loading-desc" class="sr-only">
      Loading VK authorization...
    </div>
  </div>
</template>
```

## Performance Optimization

### Lazy Loading

Implement lazy loading for VK components:

```javascript
// In router configuration
{
  path: 'vk',
  name: 'settings_inboxes_page_channel_vk',
  component: () => import(
    /* webpackChunkName: "vk-channel" */ 
    './channels/Vk.vue'
  ),
  props: true,
}
```

### Code Splitting

Split VK-specific code into separate chunks:

```javascript
// Dynamic imports for VK-specific functionality
const loadVkHelpers = () => import('./helpers/vkHelpers');
const loadVkValidators = () => import('./validators/vkValidators');
```

## Conclusion

This frontend documentation provides comprehensive guidelines for implementing VK.com integration into Chatwoot's inbox system. The implementation follows established patterns from existing social media integrations while providing VK-specific functionality.

Key implementation points:
- **OAuth Flow**: Similar to Instagram with VK-specific parameters
- **Component Structure**: Follows Vue.js best practices with proper error handling
- **State Management**: Integrates with existing Vuex store patterns
- **Internationalization**: Supports multiple languages including Russian
- **Testing**: Comprehensive unit and integration tests
- **Accessibility**: Proper ARIA labels and screen reader support
- **Performance**: Lazy loading and code splitting for optimal bundle size

The frontend implementation works in conjunction with the Ruby backend to provide a seamless VK integration experience for Chatwoot users.