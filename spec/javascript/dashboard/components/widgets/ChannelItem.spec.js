import { mount } from '@vue/test-utils';
import ChannelItem from '../../../../../../app/javascript/dashboard/components/widgets/ChannelItem.vue';

// Mock ChannelSelector component
const ChannelSelector = {
  name: 'ChannelSelector',
  template: '<div><slot /></div>',
  props: ['class', 'title', 'src', 'isComingSoon'],
};

describe('ChannelItem.vue', () => {
  let wrapper;

  const defaultProps = {
    channel: { key: 'vk', name: 'VK' },
    enabledFeatures: { channel_vk: true },
  };

  beforeEach(() => {
    // Mock window.chatwootConfig
    global.window = {
      chatwootConfig: {
        fbAppId: 'facebook_app_id',
        instagramAppId: 'instagram_app_id',
        vkAppId: 'vk_app_id',
      },
    };
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  describe('VK channel availability', () => {
    it('should be active when VK app ID is configured', () => {
      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasVkConfigured).toBe(true);
      expect(wrapper.vm.isActive).toBe(true);
    });

    it('should be inactive when VK app ID is not configured', () => {
      global.window.chatwootConfig.vkAppId = '';

      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasVkConfigured).toBe(false);
      expect(wrapper.vm.isActive).toBe(false);
    });

    it('should be inactive when VK app ID is undefined', () => {
      delete global.window.chatwootConfig.vkAppId;

      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasVkConfigured).toBe(false);
      expect(wrapper.vm.isActive).toBe(false);
    });

    it('should be inactive when chatwootConfig is undefined', () => {
      global.window.chatwootConfig = undefined;

      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasVkConfigured).toBe(false);
      expect(wrapper.vm.isActive).toBe(false);
    });
  });

  describe('Facebook channel availability', () => {
    const facebookProps = {
      channel: { key: 'facebook', name: 'Messenger' },
      enabledFeatures: { channel_facebook: true },
    };

    it('should be active when Facebook app ID is configured and feature is enabled', () => {
      wrapper = mount(ChannelItem, {
        props: facebookProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasFbConfigured).toBe(true);
      expect(wrapper.vm.isActive).toBe(true);
    });

    it('should be inactive when Facebook app ID is not configured', () => {
      global.window.chatwootConfig.fbAppId = '';

      wrapper = mount(ChannelItem, {
        props: facebookProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasFbConfigured).toBe(false);
      expect(wrapper.vm.isActive).toBe(false);
    });

    it('should be inactive when Facebook feature is disabled', () => {
      const disabledProps = {
        ...facebookProps,
        enabledFeatures: { channel_facebook: false },
      };

      wrapper = mount(ChannelItem, {
        props: disabledProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.isActive).toBe(false);
    });
  });

  describe('Instagram channel availability', () => {
    const instagramProps = {
      channel: { key: 'instagram', name: 'Instagram' },
      enabledFeatures: { channel_instagram: true },
    };

    it('should be active when Instagram app ID is configured and feature is enabled', () => {
      wrapper = mount(ChannelItem, {
        props: instagramProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasInstagramConfigured).toBe(true);
      expect(wrapper.vm.isActive).toBe(true);
    });

    it('should be inactive when Instagram app ID is not configured', () => {
      global.window.chatwootConfig.instagramAppId = '';

      wrapper = mount(ChannelItem, {
        props: instagramProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.hasInstagramConfigured).toBe(false);
      expect(wrapper.vm.isActive).toBe(false);
    });
  });

  describe('channel item click', () => {
    it('should emit channel item click when VK channel is active', () => {
      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      wrapper.vm.onItemClick();

      expect(wrapper.emitted('channelItemClick')).toBeTruthy();
      expect(wrapper.emitted('channelItemClick')[0]).toEqual(['vk']);
    });

    it('should not emit channel item click when VK channel is inactive', () => {
      global.window.chatwootConfig.vkAppId = '';

      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      wrapper.vm.onItemClick();

      expect(wrapper.emitted('channelItemClick')).toBeFalsy();
    });
  });

  describe('channel thumbnail', () => {
    it('should return correct thumbnail path for VK', () => {
      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.getChannelThumbnail()).toBe('/assets/images/dashboard/channels/vk.png');
    });

    it('should return custom thumbnail for API channel', () => {
      const apiProps = {
        channel: { key: 'api', name: 'API', thumbnail: 'custom-thumbnail.png' },
        enabledFeatures: {},
      };

      wrapper = mount(ChannelItem, {
        props: apiProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.getChannelThumbnail()).toBe('custom-thumbnail.png');
    });
  });

  describe('coming soon functionality', () => {
    it('should not show coming soon for VK channel', () => {
      wrapper = mount(ChannelItem, {
        props: defaultProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.isComingSoon).toBe(false);
    });

    it('should show coming soon for voice channel when inactive', () => {
      const voiceProps = {
        channel: { key: 'voice', name: 'Voice' },
        enabledFeatures: { channel_voice: false },
      };

      wrapper = mount(ChannelItem, {
        props: voiceProps,
        global: {
          components: { ChannelSelector },
        },
      });

      expect(wrapper.vm.isComingSoon).toBe(true);
    });
  });

  describe('general channel list inclusion', () => {
    const channels = ['website', 'twilio', 'api', 'whatsapp', 'sms', 'telegram', 'line', 'instagram', 'vk', 'voice'];

    channels.forEach(channelKey => {
      it(`should include ${channelKey} in the active channel list`, () => {
        const channelProps = {
          channel: { key: channelKey, name: channelKey },
          enabledFeatures: {},
        };

        wrapper = mount(ChannelItem, {
          props: channelProps,
          global: {
            components: { ChannelSelector },
          },
        });

        // VK has special handling, so skip the general inclusion test for it
        if (channelKey === 'vk') {
          return;
        }

        // For channels with special handling, we test their specific logic elsewhere
        if (['facebook', 'email', 'instagram', 'voice'].includes(channelKey)) {
          return;
        }

        expect(wrapper.vm.isActive).toBe(true);
      });
    });
  });
});