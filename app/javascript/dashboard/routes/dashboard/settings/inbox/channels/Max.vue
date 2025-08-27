<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    PageHeader,
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      botToken: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    botToken: { required },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const channel = await this.$store.dispatch('inboxes/createChannel', {
          channel: {
            type: 'max',
            bot_token: this.botToken,
          },
        });

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: channel.id,
          },
        });
      } catch (error) {
        useAlert(error.message || 'Unable to create MAX inbox');
      }
    },
  },
};
</script>

<template>
  <div
    class="border border-n-weak bg-n-solid-1 rounded-t-lg border-b-0 h-full w-full p-6 col-span-6 overflow-auto"
  >
    <PageHeader :header-title="'MAX'" :header-content="'Connect MAX bot token'" />
    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel()">
      <div class="flex-shrink-0 flex-grow-0">
        <label :class="{ error: v$.botToken.$error }">
          Bot Token
          <input v-model="botToken" type="text" placeholder="Enter MAX bot token" @blur="v$.botToken.$touch" />
        </label>
      </div>

      <div class="w-full mt-4">
        <NextButton :is-loading="uiFlags.isCreating" type="submit" solid blue :label="'Continue'" />
      </div>
    </form>
  </div>
  
</template>

