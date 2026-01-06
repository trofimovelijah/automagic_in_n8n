#!/bin/bash

# ============================================================================
# QUICK DATABASE SETUP - Smart License Usage Analyzer
# ============================================================================
# Быстрая загрузка данных в PostgreSQL из CSV файлов
# с поддержкой логирования ошибок воркфлоу
#
# Использование:
#   bash quick_load.sh
#   bash quick_load.sh -h 192.168.1.100 -U admin -p 5433
# ============================================================================

set -e

# Конфигурация по умолчанию
DB_HOST="${PGHOST:-localhost}"
DB_PORT="${PGPORT:-5432}"
DB_USER="${PGUSER:-postgres}"
DB_PASSWORD="${PGPASSWORD:-}"
DB_NAME="${PGDATABASE:-license_analyzer}"

# Пути к файлам
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Парсинг аргументов
while getopts "h:p:U:d:w:" opt; do
    case $opt in
        h) DB_HOST="$OPTARG" ;;
        p) DB_PORT="$OPTARG" ;;
        U) DB_USER="$OPTARG" ;;
        d) DB_NAME="$OPTARG" ;;
        w) DB_PASSWORD="$OPTARG" ;;
    esac
done

# ============================================================================
# SQL СКРИПТЫ ДЛЯ БЫСТРОЙ ЗАГРУЗКИ
# ============================================================================

echo "🚀 Smart License Usage Analyzer - Быстрая загрузка БД"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Шаг 1: Создание таблиц и функций
echo "📋 Шаг 1: Создание схемы БД..."

psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<'SCHEMA_SQL' > /dev/null

-- 1. СОЗДАНИЕ ТАБЛИЦ

-- Таблица users
CREATE TABLE IF NOT EXISTS users (
    user_id BIGINT PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    email VARCHAR(255) UNIQUE,
    organization VARCHAR(255),
    license_type VARCHAR(50) DEFAULT 'basic',
    license_limit INT DEFAULT 3,
    registered_at TIMESTAMP,
    telegram_id BIGINT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Таблица software_catalog
CREATE TABLE IF NOT EXISTS software_catalog (
    software_id SMALLINT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    cost_per_month DECIMAL(10, 2) DEFAULT 0,
    resource_weight SMALLINT DEFAULT 1,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Таблица virtual_machines
CREATE TABLE IF NOT EXISTS virtual_machines (
    vm_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    vm_name VARCHAR(255) NOT NULL,
    software_installed TEXT,
    status VARCHAR(20) DEFAULT 'active',
    created_at DATE,
    last_active TIMESTAMP,
    cpu_usage_avg SMALLINT DEFAULT 0,
    ram_usage_avg SMALLINT DEFAULT 0,
    usage_hours_week SMALLINT DEFAULT 0,
    inactivity_days SMALLINT DEFAULT 0,
    monthly_cost DECIMAL(10, 2) DEFAULT 0,
    alert_sent BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ✨ НОВАЯ ТАБЛИЦА: workflow_errors
CREATE TABLE IF NOT EXISTS workflow_errors (
    error_id SERIAL PRIMARY KEY,
    user_id BIGINT,
    error_message TEXT NOT NULL,
    error_timestamp TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    node_name TEXT,
    error_type TEXT,
    execution_mode TEXT,
    workflow_name TEXT DEFAULT 'Smart License Usage Analyzer',
    error_stack TEXT,
    context_data JSONB,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP WITHOUT TIME ZONE,
    notes TEXT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL
);

-- 2. ИНДЕКСЫ

CREATE INDEX IF NOT EXISTS idx_vm_user_id ON virtual_machines(user_id);
CREATE INDEX IF NOT EXISTS idx_vm_status ON virtual_machines(status);
CREATE INDEX IF NOT EXISTS idx_vm_created_at ON virtual_machines(created_at);
CREATE INDEX IF NOT EXISTS idx_user_telegram_id ON users(telegram_id);
CREATE INDEX IF NOT EXISTS idx_user_registered_at ON users(registered_at);

-- ✨ Индексы для workflow_errors
CREATE INDEX IF NOT EXISTS idx_workflow_errors_user_id ON workflow_errors(user_id);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_timestamp ON workflow_errors(error_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_node_name ON workflow_errors(node_name);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_resolved ON workflow_errors(resolved);
CREATE INDEX IF NOT EXISTS idx_workflow_errors_error_type ON workflow_errors(error_type);

-- 3. ПРЕДСТАВЛЕНИЯ

CREATE OR REPLACE VIEW user_vms_detail AS
SELECT
    v.vm_id,
    v.vm_name,
    u.user_id,
    u.username,
    u.telegram_id,
    v.status,
    v.monthly_cost,
    v.cpu_usage_avg,
    v.ram_usage_avg,
    v.usage_hours_week,
    v.inactivity_days,
    v.created_at,
    v.last_active,
    v.software_installed
FROM virtual_machines v
JOIN users u ON v.user_id = u.user_id
ORDER BY v.created_at DESC;

CREATE OR REPLACE VIEW user_stats AS
SELECT
    u.user_id,
    u.username,
    u.telegram_id,
    u.license_type,
    u.license_limit,
    COUNT(v.vm_id) as current_vm_count,
    SUM(v.monthly_cost) as total_monthly_cost,
    COUNT(CASE WHEN v.status = 'active' THEN 1 END) as active_vms,
    COUNT(CASE WHEN v.status = 'idle' THEN 1 END) as idle_vms,
    COUNT(CASE WHEN v.status = 'stopped' THEN 1 END) as stopped_vms
FROM users u
LEFT JOIN virtual_machines v ON u.user_id = v.user_id
GROUP BY u.user_id, u.username, u.telegram_id, u.license_type, u.license_limit;

-- ✨ Представления для ошибок
CREATE OR REPLACE VIEW unresolved_errors AS
SELECT 
    error_id,
    user_id,
    error_message,
    error_timestamp,
    node_name,
    error_type,
    workflow_name,
    EXTRACT(HOUR FROM (CURRENT_TIMESTAMP - error_timestamp)) as hours_since_error
FROM workflow_errors
WHERE resolved = false
ORDER BY error_timestamp DESC;

CREATE OR REPLACE VIEW error_stats_by_node AS
SELECT 
    node_name,
    error_type,
    COUNT(*) as error_count,
    MAX(error_timestamp) as last_error,
    COUNT(DISTINCT user_id) as affected_users
FROM workflow_errors
WHERE error_timestamp > CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY node_name, error_type
ORDER BY error_count DESC;

CREATE OR REPLACE VIEW error_stats_by_user AS
SELECT 
    u.user_id,
    u.username,
    COUNT(e.error_id) as total_errors,
    COUNT(CASE WHEN e.resolved = false THEN 1 END) as unresolved_errors,
    MAX(e.error_timestamp) as last_error
FROM users u
LEFT JOIN workflow_errors e ON u.user_id = e.user_id
WHERE e.error_timestamp > CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY u.user_id, u.username
HAVING COUNT(e.error_id) > 0
ORDER BY total_errors DESC;

-- 4. ФУНКЦИИ И ТРИГГЕРЫ

CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER IF NOT EXISTS users_update_timestamp BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER IF NOT EXISTS software_update_timestamp BEFORE UPDATE ON software_catalog FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER IF NOT EXISTS vm_update_timestamp BEFORE UPDATE ON virtual_machines FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Функции для n8n
CREATE OR REPLACE FUNCTION get_user_by_telegram(p_telegram_id BIGINT)
RETURNS TABLE (
    user_id BIGINT, username VARCHAR, full_name VARCHAR, email VARCHAR,
    organization VARCHAR, license_type VARCHAR, license_limit INT,
    registered_at TIMESTAMP, telegram_id BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT u.user_id, u.username, u.full_name, u.email, u.organization,
           u.license_type, u.license_limit, u.registered_at, u.telegram_id
    FROM users u WHERE u.telegram_id = p_telegram_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_user_vms(p_user_id BIGINT)
RETURNS TABLE (
    vm_id BIGINT, vm_name VARCHAR, status VARCHAR, created_at DATE,
    last_active TIMESTAMP, cpu_usage_avg SMALLINT, ram_usage_avg SMALLINT,
    usage_hours_week SMALLINT, inactivity_days SMALLINT,
    monthly_cost DECIMAL, software_installed TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.vm_id, v.vm_name, v.status, v.created_at, v.last_active,
           v.cpu_usage_avg, v.ram_usage_avg, v.usage_hours_week,
           v.inactivity_days, v.monthly_cost, v.software_installed
    FROM virtual_machines v WHERE v.user_id = p_user_id ORDER BY v.created_at DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_vm_by_name_or_id(p_user_id BIGINT, p_search VARCHAR)
RETURNS TABLE (
    vm_id BIGINT, vm_name VARCHAR, user_id BIGINT, status VARCHAR,
    created_at DATE, monthly_cost DECIMAL, software_installed TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.vm_id, v.vm_name, v.user_id, v.status, v.created_at,
           v.monthly_cost, v.software_installed
    FROM virtual_machines v
    WHERE v.user_id = p_user_id
    AND (CAST(v.vm_id AS VARCHAR) = p_search OR v.vm_name ILIKE '%' || p_search || '%');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION delete_vm(p_vm_id BIGINT, p_user_id BIGINT)
RETURNS TABLE (success BOOLEAN, message VARCHAR, vm_name VARCHAR, monthly_cost DECIMAL) AS $$
DECLARE
    v_vm_name VARCHAR;
    v_cost DECIMAL;
    v_user_id BIGINT;
BEGIN
    SELECT vm_name, monthly_cost, user_id INTO v_vm_name, v_cost, v_user_id
    FROM virtual_machines WHERE vm_id = p_vm_id;
    IF v_vm_name IS NULL THEN
        RETURN QUERY SELECT FALSE, 'ВМ не найдена'::VARCHAR, NULL::VARCHAR, NULL::DECIMAL;
        RETURN;
    END IF;
    IF v_user_id != p_user_id THEN
        RETURN QUERY SELECT FALSE, 'Вы не можете удалить ВМ другого пользователя'::VARCHAR, v_vm_name::VARCHAR, v_cost::DECIMAL;
        RETURN;
    END IF;
    DELETE FROM virtual_machines WHERE vm_id = p_vm_id;
    RETURN QUERY SELECT TRUE, 'ВМ успешно удалена'::VARCHAR, v_vm_name::VARCHAR, v_cost::DECIMAL;
END;
$$ LANGUAGE plpgsql;

-- ✨ Функции для логирования ошибок
CREATE OR REPLACE FUNCTION log_workflow_error(
    p_user_id BIGINT,
    p_error_message TEXT,
    p_node_name TEXT,
    p_error_type TEXT DEFAULT 'unknown',
    p_workflow_name TEXT DEFAULT 'Smart License Usage Analyzer',
    p_error_stack TEXT DEFAULT NULL,
    p_context_data JSONB DEFAULT NULL,
    p_execution_mode TEXT DEFAULT 'error_trigger'
)
RETURNS TABLE (error_id INT, success BOOLEAN) AS $$
BEGIN
    INSERT INTO workflow_errors (user_id, error_message, node_name, error_type, workflow_name, error_stack, context_data, execution_mode)
    VALUES (p_user_id, p_error_message, p_node_name, p_error_type, p_workflow_name, p_error_stack, p_context_data, p_execution_mode)
    RETURNING workflow_errors.error_id, true;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION resolve_error(p_error_id INT, p_notes TEXT DEFAULT NULL)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE workflow_errors SET resolved = true, resolved_at = CURRENT_TIMESTAMP, notes = p_notes WHERE error_id = p_error_id;
    RETURN true;
END;
$$ LANGUAGE plpgsql;

SCHEMA_SQL

echo "✅ Схема БД создана"
echo ""

# Шаг 2: Загрузка CSV данных
echo "📥 Шаг 2: Загрузка CSV данных..."

# Software Catalog
echo " ⏳ Загрузка ПО..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<SQL
COPY software_catalog (software_id, name, category, cost_per_month, resource_weight, description)
FROM '$SCRIPT_DIR/software_catalog_202601031935.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');
SQL
echo " ✅ ПО загружено"

# Users
echo " ⏳ Загрузка пользователей..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<SQL
COPY users (user_id, username, full_name, email, organization, license_type, license_limit, registered_at, telegram_id)
FROM '$SCRIPT_DIR/users_202601031936.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');
SQL
echo " ✅ Пользователи загружены"

# Virtual Machines
echo " ⏳ Загрузка виртуальных машин..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<SQL
COPY virtual_machines (vm_id, user_id, vm_name, software_installed, status, created_at, last_active, cpu_usage_avg, ram_usage_avg, usage_hours_week, inactivity_days, monthly_cost, alert_sent)
FROM '$SCRIPT_DIR/virtual_machines_202601031936.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');
SQL
echo " ✅ Виртуальные машины загружены"

echo ""

# Шаг 3: Проверка данных
echo "🔍 Шаг 3: Проверка целостности данных..."
echo ""

STATS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT
(SELECT COUNT(*) FROM users)::text || '|' ||
(SELECT COUNT(*) FROM software_catalog)::text || '|' ||
(SELECT COUNT(*) FROM virtual_machines)::text
")

IFS='|' read -r USERS_COUNT SW_COUNT VM_COUNT <<< "$STATS"

echo "📊 Статистика загруженных данных:"
echo " 👤 Пользователей: $USERS_COUNT"
echo " 💾 ПО в каталоге: $SW_COUNT"
echo " 🖥️ Виртуальных машин: $VM_COUNT"
echo ""

FK_ERRORS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
SELECT COUNT(*) FROM virtual_machines v
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.user_id = v.user_id)
")

if [ "$FK_ERRORS" -eq 0 ]; then
    echo "✅ Целостность данных: OK (нет orphan VMs)"
else
    echo "⚠️ Целостность данных: $FK_ERRORS некорректных ссылок"
fi

echo ""

# Примеры данных
echo "📝 Примеры загруженных данных:"
echo ""

echo "👤 Пользователи:"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT user_id, username, license_type, license_limit, telegram_id
FROM users LIMIT 3;"

echo ""

echo "💾 Каталог ПО:"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT software_id, name, category, cost_per_month
FROM software_catalog LIMIT 3;"

echo ""

echo "🖥️ Виртуальные машины:"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT vm_id, vm_name, status, monthly_cost
FROM virtual_machines LIMIT 3;"

echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Загрузка завершена успешно!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🔗 Параметры подключения для n8n:"
echo " Host: $DB_HOST"
echo " Port: $DB_PORT"
echo " User: $DB_USER"
echo " Database: $DB_NAME"
echo ""

echo "💡 Следующие шаги:"
echo " 1. Импортируйте оба workflow в n8n:"
echo "    - Smart-License-Usage-Analyzer.json (основной бот)"
echo "    - Global Error Handler SLUA.json (обработка ошибок)"
echo " 2. Создайте Postgres credential с параметрами выше"
echo " 3. Создайте Telegram Bot и настройте его в n8n"
echo " 4. Подключите Global Error Handler как Error Workflow основного бота"
echo " 5. Активируйте оба workflow"
echo ""
