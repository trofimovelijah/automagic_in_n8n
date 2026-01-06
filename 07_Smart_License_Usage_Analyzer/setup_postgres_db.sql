-- ============================================================================
-- Smart License Usage Analyzer - PostgreSQL Database Setup
-- ============================================================================
-- Этот скрипт создает полную схему БД для системы управления виртуальными 
-- машинами, лицензиями и логирования ошибок воркфлоу.
-- Запустить в psql перед загрузкой данных.
-- ============================================================================

-- 1. СОЗДАНИЕ ТАБЛИЦ
-- ============================================================================

-- Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    user_id BIGINT PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    email VARCHAR(255) UNIQUE,
    organization VARCHAR(255),
    license_type VARCHAR(50) DEFAULT 'basic',
    license_limit INT DEFAULT 3,
    registered_at TIMESTAMP DEFAULT NOW(),
    telegram_id BIGINT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Таблица каталога программного обеспечения
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

-- Таблица виртуальных машин
CREATE TABLE IF NOT EXISTS virtual_machines (
    vm_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    vm_name VARCHAR(255) NOT NULL,
    software_installed TEXT, -- JSON массив или CSV список ID ПО
    status VARCHAR(20) DEFAULT 'active', -- active, idle, stopped
    created_at DATE NOT NULL,
    last_active TIMESTAMP,
    cpu_usage_avg SMALLINT DEFAULT 0,
    ram_usage_avg SMALLINT DEFAULT 0,
    usage_hours_week SMALLINT DEFAULT 0,
    inactivity_days SMALLINT DEFAULT 0,
    monthly_cost DECIMAL(10, 2) DEFAULT 0,
    alert_sent BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ✨ НОВАЯ ТАБЛИЦА: Логирование ошибок воркфлоу
CREATE TABLE IF NOT EXISTS workflow_errors (
    error_id SERIAL PRIMARY KEY,
    user_id BIGINT,
    error_message TEXT NOT NULL,
    error_timestamp TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    node_name TEXT,
    error_type TEXT,           -- "runtime_error", "validation_error", "db_error", etc
    execution_mode TEXT,       -- "normal" или "error_trigger"
    workflow_name TEXT DEFAULT 'Smart License Usage Analyzer',
    error_stack TEXT,          -- для отладки
    context_data JSONB,        -- JSON с доп данными (user_input, node_params, etc)
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP WITHOUT TIME ZONE,
    notes TEXT,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL
);

-- ============================================================================
-- 2. ИНДЕКСЫ (для оптимизации запросов)
-- ============================================================================

-- Индексы для virtual_machines
CREATE INDEX idx_vm_user_id ON virtual_machines(user_id);
CREATE INDEX idx_vm_status ON virtual_machines(status);
CREATE INDEX idx_vm_created_at ON virtual_machines(created_at);

-- Индексы для users
CREATE INDEX idx_user_telegram_id ON users(telegram_id);
CREATE INDEX idx_user_registered_at ON users(registered_at);

-- ✨ Индексы для workflow_errors
CREATE INDEX idx_workflow_errors_user_id ON workflow_errors(user_id);
CREATE INDEX idx_workflow_errors_timestamp ON workflow_errors(error_timestamp DESC);
CREATE INDEX idx_workflow_errors_node_name ON workflow_errors(node_name);
CREATE INDEX idx_workflow_errors_resolved ON workflow_errors(resolved);
CREATE INDEX idx_workflow_errors_error_type ON workflow_errors(error_type);

-- ============================================================================
-- 3. ПРЕДСТАВЛЕНИЯ (views) для часто используемых запросов
-- ============================================================================

-- Представление: Все ВМ пользователя с информацией о владельце
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

-- Представление: Статистика по пользователям
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

-- ✨ Представление: Неразрешённые ошибки
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

-- ✨ Представление: Статистика ошибок по узлам
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

-- ✨ Представление: Статистика ошибок по пользователям
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

-- ============================================================================
-- 4. ТРИГГЕР для автоматического обновления updated_at
-- ============================================================================

-- Функция триггера
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггеры
CREATE TRIGGER users_update_timestamp
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER software_update_timestamp
BEFORE UPDATE ON software_catalog
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER vm_update_timestamp
BEFORE UPDATE ON virtual_machines
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

-- ============================================================================
-- 5. ФУНКЦИИ ДЛЯ N8N (хранимые процедуры)
-- ============================================================================

-- Функция: Получить пользователя по telegram_id
CREATE OR REPLACE FUNCTION get_user_by_telegram(p_telegram_id BIGINT)
RETURNS TABLE (
    user_id BIGINT,
    username VARCHAR,
    full_name VARCHAR,
    email VARCHAR,
    organization VARCHAR,
    license_type VARCHAR,
    license_limit INT,
    registered_at TIMESTAMP,
    telegram_id BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT u.user_id, u.username, u.full_name, u.email, u.organization,
           u.license_type, u.license_limit, u.registered_at, u.telegram_id
    FROM users u
    WHERE u.telegram_id = p_telegram_id;
END;
$$ LANGUAGE plpgsql;

-- Функция: Получить все ВМ пользователя
CREATE OR REPLACE FUNCTION get_user_vms(p_user_id BIGINT)
RETURNS TABLE (
    vm_id BIGINT,
    vm_name VARCHAR,
    status VARCHAR,
    created_at DATE,
    last_active TIMESTAMP,
    cpu_usage_avg SMALLINT,
    ram_usage_avg SMALLINT,
    usage_hours_week SMALLINT,
    inactivity_days SMALLINT,
    monthly_cost DECIMAL,
    software_installed TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.vm_id, v.vm_name, v.status, v.created_at, v.last_active,
           v.cpu_usage_avg, v.ram_usage_avg, v.usage_hours_week,
           v.inactivity_days, v.monthly_cost, v.software_installed
    FROM virtual_machines v
    WHERE v.user_id = p_user_id
    ORDER BY v.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Функция: Получить ВМ по имени или ID
CREATE OR REPLACE FUNCTION get_vm_by_name_or_id(p_user_id BIGINT, p_search VARCHAR)
RETURNS TABLE (
    vm_id BIGINT,
    vm_name VARCHAR,
    user_id BIGINT,
    status VARCHAR,
    created_at DATE,
    monthly_cost DECIMAL,
    software_installed TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT v.vm_id, v.vm_name, v.user_id, v.status, v.created_at,
           v.monthly_cost, v.software_installed
    FROM virtual_machines v
    WHERE v.user_id = p_user_id
    AND (CAST(v.vm_id AS VARCHAR) = p_search
         OR v.vm_name ILIKE '%' || p_search || '%');
END;
$$ LANGUAGE plpgsql;

-- Функция: Удалить ВМ и вернуть информацию о ней
CREATE OR REPLACE FUNCTION delete_vm(p_vm_id BIGINT, p_user_id BIGINT)
RETURNS TABLE (
    success BOOLEAN,
    message VARCHAR,
    vm_name VARCHAR,
    monthly_cost DECIMAL
) AS $$
DECLARE
    v_vm_name VARCHAR;
    v_cost DECIMAL;
    v_user_id BIGINT;
BEGIN
    -- Получаем данные ВМ перед удалением
    SELECT vm_name, monthly_cost, user_id INTO v_vm_name, v_cost, v_user_id
    FROM virtual_machines
    WHERE vm_id = p_vm_id;

    -- Проверяем, существует ли ВМ
    IF v_vm_name IS NULL THEN
        RETURN QUERY SELECT FALSE, 'ВМ не найдена'::VARCHAR, NULL::VARCHAR, NULL::DECIMAL;
        RETURN;
    END IF;

    -- Проверяем, принадлежит ли ВМ пользователю
    IF v_user_id != p_user_id THEN
        RETURN QUERY SELECT FALSE, 'Вы не можете удалить ВМ другого пользователя'::VARCHAR,
                           v_vm_name::VARCHAR, v_cost::DECIMAL;
        RETURN;
    END IF;

    -- Удаляем ВМ
    DELETE FROM virtual_machines WHERE vm_id = p_vm_id;

    RETURN QUERY SELECT TRUE, 'ВМ успешно удалена'::VARCHAR, v_vm_name::VARCHAR, v_cost::DECIMAL;
END;
$$ LANGUAGE plpgsql;

-- ✨ Функция: Вставить ошибку с автоматическим логированием
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
    INSERT INTO workflow_errors (
        user_id,
        error_message,
        node_name,
        error_type,
        workflow_name,
        error_stack,
        context_data,
        execution_mode
    ) VALUES (
        p_user_id,
        p_error_message,
        p_node_name,
        p_error_type,
        p_workflow_name,
        p_error_stack,
        p_context_data,
        p_execution_mode
    )
    RETURNING workflow_errors.error_id, true;
END;
$$ LANGUAGE plpgsql;

-- ✨ Функция: Резолв ошибок
CREATE OR REPLACE FUNCTION resolve_error(
    p_error_id INT,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE workflow_errors
    SET 
        resolved = true,
        resolved_at = CURRENT_TIMESTAMP,
        notes = p_notes
    WHERE error_id = p_error_id;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Конец скрипта
-- ============================================================================
-- Создано: 2026-01-06
-- Версия: 2.0 (с поддержкой логирования ошибок)
-- ============================================================================
