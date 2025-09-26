# 05. RAG на основе Google Docs и Supabase

Этот воркфлоу демонстрирует полный цикл создания и тестирования системы Retrieval-Augmented Generation (RAG). Он состоит из двух независимых, но логически связанных частей: индексации базы знаний из Google Docs и генерации ответов на вопросы с использованием этой базы[6].

## Описание

Воркфлоу позволяет превратить текстовый документ в умную базу знаний, способную давать точные ответы на вопросы, основываясь на содержащейся в ней информации[6].

### Часть 1: Индексация базы знаний

Этот процесс запускается вручную и подготавливает данные для RAG-системы.
1.  **Загрузка**: Текст базы знаний загружается из указанного документа Google Docs.
2.  **Разделение**: Текст разбивается на небольшие, семантически связанные фрагменты (чанки).
3.  **Векторизация**: Каждый чанк преобразуется в числовой вектор (эмбеддинг) с помощью модели (на выбор **OpenAI** `text-embedding-3-large` или **Hugging Face**).
4.  **Сохранение**: Текстовые чанки и их векторы загружаются в **Supabase Vector Store** для последующего поиска.

### Часть 2: Тестирование RAG

Этот процесс также запускается вручную и использует проиндексированную базу для генерации ответов.
1.  **Загрузка вопросов**: Список тестовых вопросов загружается из CSV-файла.
2.  **Поиск контекста**: Для каждого вопроса выполняется семантический поиск в Supabase, чтобы найти наиболее релевантные чанки из базы знаний.
3.  **Генерация ответа**: **AI-модель** (например, `gpt-4o-mini` через OpenRouter) получает вопрос и найденный контекст, после чего генерирует на их основе развернутый ответ.
4.  **Сохранение результатов**: Вопросы, найденный контекст и сгенерированные ответы сохраняются в итоговый файл (Google Sheets или CSV) для оценки качества работы системы.

## Ключевые компоненты

-   **Google Drive/Docs Node**: Для загрузки исходного текста.
-   **Text Splitter Node**: Для разделения текста на чанки.
-   **Embeddings Nodes (OpenAI, Hugging Face)**: Для создания векторных представлений текста.
-   **Supabase Vector Store Node**: Для хранения векторов и выполнения семантического поиска.
-   **AI Agent (Chain)**: Для генерации ответов на основе контекста.
-   **HTTP Request / Read Binary File**: Для загрузки CSV-файла с вопросами.

## Настройка и запуск

1.  **Импорт**: Загрузите `workflow.json` в ваш n8n.
2.  **Настройка кредов**:
    -   **Google**: Настройте учетные данные для Google Drive/Docs.
    -   **Supabase**: Укажите ключи для подключения к вашему проекту Supabase.
    -   **AI-провайдеры**: Введите API-ключи для OpenAI, Hugging Face и/или OpenRouter.
3.  **Индексация**: Запустите вручную ветку индексации, указав ID вашего Google-документа.
4.  **Тестирование**: После успешной индексации запустите вручную ветку тестирования, указав URL к вашему CSV-файлу с вопросами.

## Особенности настройки векторного хранилища
### Инструкция для создания таблиц в Supabase для эмбеддингов от OpenAI
Таблица `documents` используется для загрузки данных в базу знаний.

Вставьте код ниже в SQL Editor в интерфейсе Supabase:
```sql
-- Enable the pgvector extension to work with embedding vectors
create extension vector;

-- Create a table to store your documents
CREATE TABLE public.documents (
  id BIGSERIAL NOT NULL,
  content TEXT NULL,
  metadata JSONB NULL,
  embedding public.vector NULL,
  CONSTRAINT documents_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;


-- Create a function to search for documents
create or replace function match_documents (
  query_embedding vector(1536),
  match_count int default null,
  filter jsonb DEFAULT '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;
```
Таблица `message_history` используется для хранения истории переписок:
```sql
create table public.message_history (
 id serial not null,
 session_id text not null,
 user_id text null,
 username text null,
 role text null,
 content text null,
 metadata jsonb null,
 created_at timestamp with time zone null default now(),
 first_name text null,
 constraint chat_logs_pkey primary key (id)
) TABLESPACE pg_default;
```

### Инструкция для создания таблиц в Supabase для эмбеддингов другой размерности
Если используете эмбеддинги, например, `cointegrated/LaBSE-en-ru`, тогда необходимо подготовить хранилище для работы с векторами другой размерности
Полная очистка старой схемы:
```sql
-- Удаляем старую функцию и таблицу для чистой установки
DROP FUNCTION IF EXISTS public.match_documents;
DROP TABLE IF EXISTS public.documents;
```
Создание новой схемы
```sql
-- 1. Включаем расширение pgvector
create extension if not exists vector;

-- 2. Создаем таблицу с ПРАВИЛЬНОЙ размерностью векторов (768)
CREATE TABLE public.documents (
  id BIGSERIAL NOT NULL,
  content TEXT NULL,
  metadata JSONB NULL,
  embedding public.vector(768) NULL, -- Ключевое изменение здесь
  CONSTRAINT documents_pkey PRIMARY KEY (id)
);

-- 3. Создаем функцию поиска с ПРАВИЛЬНОЙ размерностью векторов (768)
create or replace function match_documents (
  query_embedding vector(768), -- Ключевое изменение здесь
  match_count int default null,
  filter jsonb DEFAULT '{}'
) returns table (
  id bigint,
  content text,
  metadata jsonb,
  similarity float
)
language plpgsql
as $$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (documents.embedding <=> query_embedding) as similarity
  from documents
  where metadata @> filter
  order by documents.embedding <=> query_embedding
  limit match_count;
end;
$$;
```
На всякий случай очистите таблицу в Supabase, чтобы быть на 100% уверенным, что в базе не осталось "испорченных" данных без векторов:
```sql
TRUNCATE TABLE public.documents;
```