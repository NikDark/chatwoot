# Настройка VK ID OAuth 2.1

Данная документация описывает настройку авторизации через VK ID в соответствии с новой спецификацией OAuth 2.1.

## Изменения согласно новой документации

### Основные особенности VK ID OAuth 2.1:
1. **Обязательное использование PKCE** - для защиты от атак перехвата authorization code
2. **Новые эндпоинты**:
   - Авторизация: `https://id.vk.com/authorize`
   - Обмен токенов: `https://id.vk.com/oauth2/auth`
   - Получение данных пользователя: `https://id.vk.com/oauth2/user_info`
3. **Параметр state** - для защиты от CSRF атак
4. **Новый флоу токенов** - Access token + Refresh token + ID token

## Настройка окружения

### 1. Переменные окружения

Добавьте следующие переменные в ваш `.env` файл:

```bash
# VK ID OAuth 2.1 Configuration
VK_ID_CLIENT_ID=your_vk_app_id
VK_ID_CLIENT_SECRET=your_vk_app_secret
VK_ID_CALLBACK_URL=https://yourdomain.com/auth/vk_id/callback
```

### 2. Настройка VK приложения

1. Зайдите в [VK для разработчиков](https://dev.vk.com/)
2. Создайте новое приложение или используйте существующее
3. В настройках приложения укажите:
   - **Redirect URI**: `https://yourdomain.com/auth/vk_id/callback`
   - **Доступные права**: `email` (минимум)

## Компоненты интеграции

### 1. OmniAuth стратегия
- **Файл**: `lib/omniauth/strategies/vk_id.rb`
- **Особенности**: 
  - Поддержка PKCE (code_challenge + code_verifier)
  - Валидация state параметра
  - Обработка новых эндпоинтов VK ID

### 2. Контроллер обратных вызовов
- **Файл**: `app/controllers/devise_overrides/omniauth_callbacks_controller.rb`
- **Функции**:
  - Обработка успешной авторизации через VK ID
  - Сохранение токенов в `custom_attributes`
  - Создание учетной записи пользователя

### 3. Сервис управления токенами
- **Файл**: `app/services/vk_id/token_service.rb`
- **Возможности**:
  - Обновление Access token через Refresh token
  - Получение информации о пользователе
  - Отзыв токенов
  - Проверка истечения токенов

### 4. Фронтенд компонент
- **Файл**: `app/javascript/v3/components/VkOauth/Button.vue`
- **Особенности**:
  - Генерация PKCE параметров на клиенте
  - Формирование правильного URL для авторизации
  - Сохранение state и code_verifier в sessionStorage

## Использование

### Обновление токенов

```ruby
# Получение сервиса для пользователя
token_service = VkId::TokenService.new(user)

# Обновление токена
if token_service.refresh_token!
  puts "Token updated successfully"
else
  puts "Failed to refresh token"
end

# Получение актуального токена
access_token = token_service.valid_access_token
```

### Получение информации о пользователе

```ruby
token_service = VkId::TokenService.new(user)
user_info = token_service.get_user_info

if user_info
  puts "User ID: #{user_info['user']['user_id']}"
  puts "Email: #{user_info['user']['email']}"
else
  puts "Failed to get user info"
end
```

## Безопасность

### Реализованные меры защиты:

1. **PKCE (Proof Key for Code Exchange)**:
   - `code_verifier` генерируется на клиенте
   - `code_challenge` создается из `code_verifier` с помощью SHA256
   - Защищает от атак перехвата authorization code

2. **State параметр**:
   - Генерируется случайная строка
   - Сохраняется в сессии
   - Проверяется при возврате из VK ID
   - Защищает от CSRF атак

3. **Валидация токенов**:
   - Проверка истечения срока действия
   - Безопасное хранение в `custom_attributes`
   - Возможность отзыва токенов

## Локализация

Добавлены переводы для кнопки авторизации:
- **Английский**: "Login with VK ID"
- **Русский**: "Войти через VK ID"

Для добавления других языков, обновите соответствующие файлы в `app/javascript/dashboard/i18n/locale/`.

## Отладка

### Логи авторизации

Все ошибки VK ID авторизации логируются в Rails.logger:
- Ошибки OAuth процесса
- Проблемы с обновлением токенов
- Ошибки получения пользовательских данных

### Проверка конфигурации

```ruby
# В Rails console
puts "VK ID Client ID: #{ENV['VK_ID_CLIENT_ID']}"
puts "VK ID Callback URL: #{ENV['VK_ID_CALLBACK_URL']}"

# Проверка наличия VK данных у пользователя
user = User.find(1)
vk_data = user.custom_attributes&.dig('vk_id')
puts "VK data present: #{vk_data.present?}"
```

## Обновление с предыдущих версий

Если у вас была старая интеграция с VK OAuth 2.0:

1. Обновите URL авторизации с `oauth.vk.com` на `id.vk.com`
2. Добавьте поддержку PKCE в клиентской части
3. Обновите обработку токенов для поддержки ID token
4. Измените эндпоинт получения пользовательских данных

## Ссылки

- [Официальная документация VK ID OAuth 2.1](https://id.vk.com/about/business/go/docs/ru/vkid/latest/vk-id/connection/realization)
- [Спецификация PKCE (RFC 7636)](https://tools.ietf.org/html/rfc7636)
- [OAuth 2.1 Draft](https://tools.ietf.org/html/draft-ietf-oauth-v2-1)