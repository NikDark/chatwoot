# VK Integration Updates - December 2024

## Обновления VK интеграции в соответствии с новой документацией VK ID

### Основные изменения

#### 1. Исправлена проблема с доступностью VK в интерфейсе

**Проблема:** После настройки VK credentials в SuperAdmin, канал VK оставался недоступным в интерфейсе создания инбоксов.

**Решение:**
- Добавлен `vkAppId` в `window.chatwootConfig` в `app/views/layouts/vueapp.html.erb`
- Обновлен `ChannelItem.vue` для проверки конфигурации VK через `hasVkConfigured()`
- Добавлена проверка VK в метод `isActive()` компонента ChannelItem
- Включен 'vk' в список доступных каналов

**Файлы изменены:**
- `app/views/layouts/vueapp.html.erb` - добавлен `vkAppId`
- `app/javascript/dashboard/components/widgets/ChannelItem.vue` - добавлена логика проверки VK

#### 2. Обновлен OAuth функционал согласно VK ID

**Изменения:**
- Обновлен URL авторизации с `https://oauth.vk.com/authorize` на `https://id.vk.com/auth`
- Обновлен URL обмена токенов с `https://oauth.vk.com/access_token` на `https://id.vk.com/oauth2/auth`
- Добавлен параметр `grant_type: 'authorization_code'` для соответствия OAuth 2.0
- Изменен порядок scope параметров на `'groups,messages'`

**Файлы изменены:**
- `app/controllers/concerns/vk_concern.rb` - обновлен URL авторизации
- `app/controllers/vk/callbacks_controller.rb` - обновлен URL обмена токенов

#### 3. Улучшена безопасность OAuth flow

**Новые возможности:**
- Secure state parameter с подписью через `ActiveSupport::MessageVerifier`
- Валидация timestamp в state parameter (защита от replay атак)
- Проверка соответствия account_id в state parameter
- Время жизни state parameter ограничено 1 часом

**Файлы изменены:**
- `app/controllers/api/v1/accounts/vk/authorizations_controller.rb` - генерация secure state
- `app/controllers/vk/callbacks_controller.rb` - валидация state parameter

#### 4. Comprehensive Test Coverage

**Новые тесты:**
- Frontend configuration tests (`spec/views/layouts/vueapp_html_erb_spec.rb`)
- Channel availability tests (`spec/javascript/dashboard/components/widgets/ChannelItem.spec.js`)
- System integration tests (`spec/system/vk_channel_availability_spec.rb`)
- OAuth security tests (обновлены существующие тесты)
- Integration tests (`spec/integration/vk_integration_spec.rb`)

### Конфигурация SuperAdmin

VK канал теперь корректно появляется в интерфейсе после настройки следующих параметров в SuperAdmin:

1. **VK_APP_ID** - ID приложения VK
2. **VK_APP_SECRET** - Секретный ключ приложения VK  
3. **VK_VERIFY_TOKEN** - Токен для верификации webhook
4. **VK_WEBHOOK_SECRET** - Секретный ключ для подписи webhook
5. **VK_API_VERSION** - Версия VK API (по умолчанию 5.131)

### Обратная совместимость

Все изменения сохраняют полную обратную совместимость:
- Существующий функционал Facebook и Instagram не затронут
- VK интеграция следует тем же паттернам что и другие социальные каналы
- Существующие тесты продолжают работать
- Структура базы данных остается прежней

### OAuth Flow безопасности

Новый flow OAuth включает:
1. **Генерация state parameter** с account_id и timestamp
2. **Подпись state parameter** через Rails secret_key_base
3. **Валидация state** при получении callback
4. **Проверка срока действия** state parameter (1 час)
5. **Проверка account_id** для предотвращения CSRF

### Endpoints VK ID

Обновлены на современные VK ID endpoints:
- **Авторизация:** `https://id.vk.com/auth`
- **Обмен токенов:** `https://id.vk.com/oauth2/auth`
- **Параметры:** добавлен `grant_type=authorization_code`

### Тестирование

Для предотвращения повторения проблем добавлены тесты:

1. **Unit tests** - проверка отдельных компонентов
2. **Integration tests** - проверка полного workflow
3. **System tests** - проверка UI взаимодействия
4. **Security tests** - проверка OAuth безопасности

### Файлы с изменениями

#### Backend (Ruby)
- `app/views/layouts/vueapp.html.erb`
- `app/controllers/concerns/vk_concern.rb`
- `app/controllers/vk/callbacks_controller.rb`
- `app/controllers/api/v1/accounts/vk/authorizations_controller.rb`

#### Frontend (JavaScript)
- `app/javascript/dashboard/components/widgets/ChannelItem.vue`

#### Tests
- `spec/views/layouts/vueapp_html_erb_spec.rb` (новый)
- `spec/javascript/dashboard/components/widgets/ChannelItem.spec.js` (новый)
- `spec/system/vk_channel_availability_spec.rb` (новый)
- `spec/integration/vk_integration_spec.rb` (новый)
- `spec/controllers/vk/callbacks_controller_spec.rb` (обновлен)
- `spec/controllers/api/v1/accounts/vk/authorizations_controller_spec.rb` (обновлен)

#### Assets
- `public/assets/images/dashboard/channels/vk.png` (добавлен)

### Проверка работоспособности

После обновления:
1. SuperAdmin должен настроить VK_APP_ID в Installation Configs
2. VK канал должен появиться в списке доступных каналов
3. Clicking на VK должен открыть форму OAuth авторизации
4. OAuth flow должен использовать новые VK ID endpoints
5. Созданный VK инбокс должен работать как и другие социальные каналы

Все существующие функции Instagram, Facebook и других каналов остаются без изменений.