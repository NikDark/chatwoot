# VK Двухэтапная авторизация для множественных групп

## Обзор

Реализована двухэтапная система авторизации VK для подключения множественных групп VK к Chatwoot согласно [официальной документации VK](https://id.vk.com/about/business/go/docs/ru/vkid/latest/oauth/oauth-vkontakte/authcode-flow-community).

## Архитектура

### Этап 1: Авторизация пользователя
**Контроллер:** `Api::V1::Accounts::Vk::AuthorizationsController`
**Callback:** `Vk::CallbacksController` (`/vk/callback`)

1. Пользователь инициирует подключение VK
2. Генерируется URL авторизации с `scope=groups`
3. Пользователь авторизуется и разрешает доступ к списку групп
4. Получается access_token пользователя
5. Запрашивается список администрируемых групп через `groups.get` с `filter=admin`
6. Генерируется URL для авторизации групп с параметром `group_ids`
7. Автоматическое перенаправление на этап 2

### Этап 2: Авторизация групп
**Callback:** `Vk::GroupsCallbacksController` (`/vk/groups_callback`)

1. Пользователь автоматически перенаправляется для авторизации групп
2. VK запрашивает разрешения для всех администрируемых групп
3. Получаются access_token'ы для каждой группы
4. Создаются каналы Chatwoot для каждой группы
5. Создаются inbox'ы для каждого канала

## Измененные файлы

### 1. `app/controllers/vk/callbacks_controller.rb`
- **Изменения:** Переделан для этапа 1 - получение списка групп пользователя
- **Новые методы:** `fetch_user_admin_groups()`
- **Логика:** Получает список групп и перенаправляет на авторизацию групп

### 2. `app/controllers/vk/groups_callbacks_controller.rb` (НОВЫЙ)
- **Назначение:** Обработка callback'а авторизации групп
- **Ключевые методы:**
  - `process_groups_authorization()` - основная логика
  - `exchange_code_for_group_tokens()` - обмен кода на токены групп
  - `fetch_single_group_info()` - получение информации о группе
  - `find_or_create_channel()` - создание/обновление каналов
  - `create_or_update_inbox()` - создание inbox'ов

### 3. `app/controllers/concerns/vk_concern.rb`
- **Добавлено:** 
  - `vk_groups_authorization_url()` - генерация URL для авторизации групп
  - `vk_groups_callback_url()` - URL callback'а для групп

### 4. `config/routes.rb`
- **Добавлено:** `get 'vk/groups_callback', to: 'vk/groups_callbacks#show'`

## Поток данных

```
[Пользователь] 
    ↓ (Нажимает "Подключить VK")
[AuthorizationsController#create] 
    ↓ (Генерирует URL авторизации пользователя)
[VK OAuth - Этап 1] 
    ↓ (Пользователь разрешает доступ к группам)
[CallbacksController#show] 
    ↓ (Получает токен пользователя, список групп)
[VK OAuth - Этап 2] 
    ↓ (Автоматическое перенаправление с group_ids)
[GroupsCallbacksController#show] 
    ↓ (Получает токены групп)
[Создание каналов и inbox'ов]
    ↓
[Успешное подключение]
```

## Параметры авторизации

### Этап 1 (Пользователь):
```
https://oauth.vk.com/authorize?
  response_type=code&
  client_id={APP_ID}&
  redirect_uri={CALLBACK_URL}&
  scope=groups&
  state={ACCOUNT_ID}
```

### Этап 2 (Группы):
```
https://oauth.vk.com/authorize?
  response_type=code&
  client_id={APP_ID}&
  redirect_uri={GROUPS_CALLBACK_URL}&
  group_ids={COMMA_SEPARATED_GROUP_IDS}&
  scope=messages,manage&
  state={REDIS_STATE}&
  v=5.131
```

## Ответ VK на авторизацию групп

Согласно документации, VK возвращает JSON с токенами для каждой группы:

```json
{
  "access_token_123456": "533bacf01e11f55b536a565b57531ac114461ae8736d6506a3",
  "access_token_654321": "a740d2bfe91caaa6eab794e1168da38cdaedc93c92f233638f",
  "groups": [
    {
      "group_id": 123456,
      "access_token": "533bacf01e11f55b536a565b57531ac114461ae8736d6506a3"
    },
    { 
      "group_id": 654321,
      "access_token": "a740d2bfe91caaa6eab794e1168da38cdaedc93c92f233638f"
    }
  ],
  "expires_in": 0
}
```

## Обработка ошибок

- **Нет администрируемых групп:** Пользователь перенаправляется с ошибкой
- **Ошибки токенов:** Логируются и пользователь перенаправляется на страницу ошибки
- **Истекшие состояния:** Обработка через Redis state management

## Преимущества новой системы

1. **Множественные группы:** Теперь можно подключить все администрируемые группы за один раз
2. **Соответствие VK API:** Следует официальной документации VK
3. **Безопасность:** Использует state parameters и Redis для временного хранения данных
4. **Отказоустойчивость:** Детальная обработка ошибок на каждом этапе

## Миграция с предыдущей версии

Существующие подключения VK продолжат работать. Новые подключения будут использовать двухэтапную авторизацию для поддержки множественных групп.

## Тестирование

Для тестирования новой функциональности:

1. Убедитесь, что у вас есть VK приложение с настроенными `VK_APP_ID` и `VK_APP_SECRET`
2. Настройте корректные callback URL'ы в настройках VK приложения
3. Убедитесь, что тестовый пользователь является администратором хотя бы одной VK группы
4. Протестируйте полный поток от авторизации до создания каналов

## Конфигурация

Требуемые переменные окружения:
- `VK_APP_ID` - ID VK приложения
- `VK_APP_SECRET` - Secret key VK приложения
- `VK_API_VERSION` - Версия VK API (по умолчанию 5.131)
- `FRONTEND_URL` - URL фронтенда для формирования callback URL'ов