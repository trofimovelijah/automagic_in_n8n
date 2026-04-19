# 🚀 Smart License Usage Analyzer

Телеграм-бот для управления виртуальными машинами и лицензиями, интегрированный с n8n. Позволяет пользователям создавать ВМ, отслеживать использование ресурсов, анализировать неактивные машины и удалять ненужные ВМ.

## 📋 Возможности

✅ **Управление ВМ**
- Создание новых виртуальных машин с выбранным ПО
- Просмотр списка всех своих ВМ
- Удаление неиспользуемых ВМ (по ID или имени)
- Просмотр детальной информации о конкретной ВМ

✅ **Контроль лицензий**
- Автоматическая проверка лимита лицензии перед созданием ВМ
- Отслеживание использования лицензий по типам (basic, standard, premium)
- Учет стоимости содержания ВМ

✅ **Анализ ресурсов**
- Мониторинг использования CPU и RAM
- Выявление неактивных ВМ (простой более 3 дней)
- Рекомендации по оптимизации ресурсов
- Отправка alert'ов при превышении порогов

✅ **Интеграция**
- Telegram Bot API для удобного интерфейса
- PostgreSQL для хранения данных
- n8n для автоматизации процессов
- Redis для кэширования (опционально)

## 🗂️ Структура проекта

```bash
smart-license-analyzer/
├── Smart-License-Usage-Analyzer.json   # основное n8n воркфлоу
├── Global Error Handler SLUA.json      # воркфлоу n8n для отправки ошибок в ходе выполнения основного воркфлоу
├── setup_postgres_db.sql               # Инициализация БД
├── load_data.sh                        # Скрипт загрузки CSV данных
└── README.md                           # Этот файл
```

## 📦 Требования

- **PostgreSQL 16+** — база данных для хранения информации о ВМ, ПО и пользователях
- **n8n 0.180+** — платформа для создания автоматизации и воркфлоу
- **Telegram Bot** — bot token для работы с Telegram API
- **Python 3.8+** или **Bash** — для скриптов загрузки данных
- **Redis** — хранение состояний
- **psql** (PostgreSQL client) — для выполнения SQL скриптов

## 🚀 Быстрый старт

### 1️⃣ Подготовка PostgreSQL

#### Вариант A: Локальная установка

```bash
# Установка PostgreSQL (MacOS)
brew install postgresql

# Установка PostgreSQL (Ubuntu/Debian)
sudo apt-get install postgresql postgresql-contrib

# Запуск сервера PostgreSQL
sudo systemctl start postgresql

# Проверка версии
psql --version
```

#### Вариант B: Docker

```bash
docker run --name postgres-smart-license \
  -e POSTGRES_PASSWORD=your_secure_password \
  -e POSTGRES_DB=license_analyzer \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  -d postgres:14

# Проверка подключения
docker exec -it postgres-smart-license psql -U postgres -d license_analyzer -c "SELECT 1;"
```

### 2️⃣ Инициализация схемы БД

```bash
# Запустить SQL скрипт для создания таблиц, индексов и функций
psql -h localhost -U postgres -d license_analyzer -f setup_postgres_db.sql

# Вывод при успехе: CREATE TABLE (несколько раз), CREATE INDEX и т.д.
```

### 3️⃣ Загрузка CSV данных

```bash
# Сделать скрипт исполняемым
chmod +x load_data.sh

# Запустить загрузку (использует переменные окружения или аргументы)
./load_data.sh -h localhost -U postgres -d license_analyzer

# Или с переменными окружения
export PGHOST=localhost PGUSER=postgres PGDATABASE=license_analyzer
./load_data.sh
```

**Ожидаемый вывод:**
```
✅ Все CSV файлы найдены
✅ Подключение к БД успешно
✅ Схема БД создана
✅ software_catalog загружена (8 записей)
✅ users загружена (9 записей)
✅ virtual_machines загружена (13 записей)
✅ Все данные загружены

📊 Статистика загруженных данных:
  Пользователей | 9
  ПО в каталоге | 8
  Виртуальных машин | 13
```

### 4️⃣ Проверка данных в БД

```bash
# Подключиться к БД
psql -h localhost -U postgres -d license_analyzer

# В интерпретаторе psql выполнить:
SELECT user_id, username, telegram_id, license_type FROM users LIMIT 5;
SELECT COUNT(*) FROM virtual_machines;
SELECT * FROM software_catalog;

# Выход
\q
```

### 5️⃣ Настройка n8n

1. **Создать Telegram Bot**
   ```
   - Напишите @BotFather в Telegram
   - Выполните /newbot
   - Сохраните API token
   ```

2. **Импортировать workflow**
   ```
   - Откройте n8n dashboard
   - Нажмите "Import"
   - Выберите [Smart-License-Usage-Analyzer.json](/07_Smart_License_Usage_Analyzer/Smart%20License%20Usage%20Analyzer.json)
   - Нажмите "Import Workflow"
   - Выполните аналогичные действия для [Global Error Handler SLUA.json](/07_Smart_License_Usage_Analyzer/Global%20Error%20Handler%20SLUA.json)
   ```

3. **Настроить Postgres подключение**
   - В n8n перейдите в "Credentials"
   - Создайте новое "PostgreSQL" соединение
   - Заполните:
     ```
     Host: localhost (или IP сервера)
     Port: 5432
     User: postgres
     Password: [ваш пароль]
     Database: license_analyzer
     SSL: false (для локального, true для production)
     ```
   - Нажмите "Test Connection"

4. **Настроить Telegram Bot**
   - В n8n перейдите в "Credentials"
   - Создайте новое "Telegram" соединение
   - Заполните API token bot'а
   - Нажмите "Test Connection"

5. **Активировать workflow**
   - Откройте импортированный workflow
   - Нажмите "Activate"
   - Бот начнет отвечать на сообщения

## 💬 Команды Telegram Bot

| Команда | Описание | Параметры |
|---------|---------|-----------|
| `/createvm` | Создать новую ВМ | Пример: `/createvm 1,2,3` (ID ПО через запятую) |
| `/myresources` | Показать все мои ВМ | — |
| `/vmdetails` | Информация о ВМ | Пример: `/vmdetails 123` или `/vmdetails Analysis-Server` |
| `/softwarecatalog` | Список доступного ПО | — |
| `/delete` | Удалить ВМ | Пример: `/delete 123` или `/delete Analysis-Server` |
| `/optimize` | Рекомендации по оптимизации | — |
| `/checkidle` | Найти неактивные ВМ | — |
| `/help` | Справка по командам | — |

### Примеры использования

```
👤 Пользователь: /createvm 1,5
🤖 Бот: ✅ ВМ создана!
   Название: VM-1-234567-AUT
   Установленное ПО: AutoCAD, MatLab
   Статус: active
   Стоимость: 5500₽/мес

👤 Пользователь: /myresources
🤖 Бот: [Список всех ВМ пользователя]

👤 Пользователь: /delete VM-1-234567-AUT
🤖 Бот: ✅ ВМ удалена успешно!
   Название: VM-1-234567-AUT
   Экономия: 5500₽/мес

👤 Пользователь: /vmdetails Analysis-Server
🤖 Бот: [Детальная информация о ВМ]
```

## 🏗️ Архитектура Workflow

Workflow состоит из нескольких основных блоков:

### 1. **Webhook - Telegram Bot** 
Точка входа, получает сообщения от пользователя

### 2. **Command Router**
Switch-узел маршрутизирует команды:
- `/createvm` → Создание ВМ
- `/myresources`, `/softwarecatalog`, `/vmdetails` → Просмотр
- `/optimize`, `/checkidle` → Анализ
- `/delete` → Удаление ВМ
- `/help` → Справка
- Остальное → User Input

### 3. **Get User for [Action]**
SQL запрос получает пользователя по telegram_id:
```sql
SELECT * FROM users WHERE telegram_id = $1
```

### 4. **Load Data**
Загружает нужные данные из БД (ВМ, ПО, статистика)

### 5. **Process & Format**
Code-узлы обрабатывают данные и форматируют сообщения

### 6. **Database Operations**
Postgres узлы выполняют операции с БД:
- INSERT для создания ВМ
- SELECT для получения данных
- DELETE для удаления ВМ

### 7. **Send Message**
Telegram узел отправляет результат пользователю

## 🗄️ Схема БД

### Таблица `users`
```sql
user_id          BIGINT PRIMARY KEY
username         VARCHAR(100) UNIQUE
full_name        VARCHAR(255)
email            VARCHAR(255) UNIQUE
organization     VARCHAR(255)
license_type     VARCHAR(50) -- 'basic', 'standard', 'premium'
license_limit    INT         -- Максимум ВМ для лицензии
registered_at    TIMESTAMP
telegram_id      BIGINT UNIQUE
```

### Таблица `software_catalog`
```sql
software_id      SMALLINT PRIMARY KEY
name             VARCHAR(100)
category         VARCHAR(50) -- 'CAD', 'CAE', 'Programming', 'Database'
cost_per_month   DECIMAL(10,2)
resource_weight  SMALLINT   -- 1-5, вес в единицах ресурса
description      TEXT
```

### Таблица `virtual_machines`
```sql
vm_id            BIGINT PRIMARY KEY
user_id          BIGINT FOREIGN KEY -> users(user_id)
vm_name          VARCHAR(255)
software_installed TEXT      -- JSON или CSV список ID ПО
status           VARCHAR(20) -- 'active', 'idle', 'stopped'
created_at       DATE
last_active      TIMESTAMP
cpu_usage_avg    SMALLINT    -- 0-100 %
ram_usage_avg    SMALLINT    -- 0-100 %
usage_hours_week SMALLINT    -- Часов в неделю
inactivity_days  SMALLINT    -- Дней без активности
monthly_cost     DECIMAL(10,2)
alert_sent       BOOLEAN
```

## 📚 Ресурсы

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Telegram Node](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.telegram/)
- [n8n PostgreSQL Node](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.postgres/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Telegram Bot API](https://core.telegram.org/bots/api)

## 📝 Лицензия

MIT License - смотрите файл [LICENSE](../LICENSE)

---
