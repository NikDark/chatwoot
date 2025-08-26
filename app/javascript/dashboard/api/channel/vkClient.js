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