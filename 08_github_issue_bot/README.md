# 08 GitHub Issue Bot

Telegram-бот для создания и просмотра GitHub Issues по текстовой команде через `n8n`.

## Пример использования
```bash
Пользователь: "Создай issue: Исправить баг с авторизацией в репо myproject"
Бот: "✅ Issue #42 создан: https://github.com/user/myproject/issues/42"
```
![пример использования](demo.gif)

## Стек
| Компонент       | Технология                       |
|-----------------|----------------------------------|
| Триггер         | Telegram Bot API                 |
| Хранение токена | Redis (`github_token_<user_id>`) |
| AI-агент        | OpenRouter (LLM)                 |
| Интеграция      | GitHub API                       |

## Архитектура воркфлоу
```bash
Telegram Trigger
├── Extract Fields (user_id, text, chat_id)
├── Redis: GET github_token_<user_id> ← авторизация
├── AI Agent (OpenRouter LLM)
├── GitHub Tool: create_issue / get_issue
└── Telegram: отправить ответ
```

## Ключевые узлы

### 1. `3a Get Token` (Redis)
- **Операция:** `GET`
- **Ключ:** `github_token_{{ $json.user_id }}`
- **Назначение:** получить персональный GitHub токен пользователя из Redis (db `k3rZiJXMKohxs4tn`)
- ⚠️ Если токен не найден — бот не сможет работать с GitHub API

### 2. AI Agent (n8n-nodes-langchain.agent)
- **LLM:** OpenRouter Chat Model
- **Инструменты:** GitHub-нода (create/read issues)
- Агент интерпретирует команды на естественном языке и вызывает нужный GitHub endpoint

### 3. Telegram (вход и выход)
- Триггер принимает `message` и `callback_query`
- Финальный узел отправляет результат обратно пользователю

## Переменные окружения / Credentials
| Переменная | Описание |
|-----------|---------|
| Redis `Redis beget 47` | Хранение GitHub токенов |
| OpenRouter API | LLM для обработки команд |
| Telegram Bot API | Бот redFlags |

## Известные ограничения
- Токен хранится в Redis — при перезапуске Redis токены сохраняются (если persistence включён)
- Один пользователь = один GitHub токен