# 09. Телеграм-бот поиска "Красных флажков" в юридических документах

> 📖 Более подробно с документацией по проекту можно ознакомиться на https://trofimovelijah.github.io/red-flag-analysis/

RAG-бот для юридического анализа документов (договоров, пользовательских соглашений). Находит «красные флажки» — потенциально опасные условия — используя векторную базу Qdrant.

![Обзор воркфлоу](demo.gif)

---

## Стек

| Компонент | Технология |
|-----------|-----------|
| Триггер | Telegram Bot API |
| Состояния (FSM) | Redis |
| Хранение файлов | MinIO (S3-совместимый) |
| Векторная БД | Qdrant (`ru_documents_embeddings`) |
| Эмбеддинги | HuggingFace `intfloat/multilingual-e5-base` |
| LLM | OpenRouter (temperature 0.2) |
| Реляционная БД | PostgreSQL (схема `red_flag`) |

---

## Архитектура

```
📱 Telegram Gateway
    └─► 🔑 Session & Rate Limit (Redis FSM)
            └─► 📄 Document Parser (PDF/TXT → чанки)
                    └─► 🐕 RAG Pipeline (Qdrant + AI Agent)
                            └─► 🐘 PostgreSQL
                                    └─► 📤 Telegram Response
```

### FSM — состояния сессии

```
IDLE
 ├─► [btn_add_text]       → AWAITING_TEXT → TEXT_ENTERED
 ├─► [btn_add_file]       → AWAITING_FILE → FILE_UPLOADED
 └─► [btn_analyze_start]  → ANALYZING → IDLE
```

---

## Ключевые узлы

### Rate Limit
- Ключ Redis: `limit:<telegram_id>:daily`
- Лимит: **3 запроса в день** (тариф Free), TTL до конца дня по `Europe/Moscow`
- При превышении — предложение перейти на тариф Pro

### Document Parser
Файл загружается в MinIO через AWS4-подпись (реализована вручную в Code-ноде).  
При анализе: MinIO → Extract from PDF → чанки по **2000 символов** с перекрытием **300 символов**.

### RAG Pipeline
AI Agent получает чанк, обязательно вызывает инструмент поиска по `ru_documents_embeddings` и возвращает структурированный JSON:

```json
{
  "document_type": "Пользовательское соглашение",
  "jurisdiction": "РФ",
  "risks": [
    {
      "risk_name": "Одностороннее изменение условий",
      "severity": "HIGH",
      "confidence_score": 0.92,
      "evidence_text": "...",
      "recommendation": "..."
    }
  ],
  "summary_html": "<b>📋 Тип документа:</b> ..."
}
```

### PostgreSQL (схема `red_flag`)

| Таблица | Назначение |
|---------|-----------|
| `users` | Пользователи (UPSERT по `telegram_id`) |
| `sessions` | Сессия = один документ |
| `chunks` | Фрагменты документа |
| `analysis_results` | Найденные риски |
| `audit_logs` | Журнал действий |

---

## Известные ограничения

- **S3 + MinIO:** стандартная n8n S3-нода возвращает 403 при кастомном endpoint — используется `HTTP Request` с ручной AWS4-подписью (баг открыт с 2022 г.)
- **Credentials в коде:** `accessKey` и `secretKey` захардкожены в Code-нодах — в продакшене заменить на `$env.N8N_MINIO_*`.