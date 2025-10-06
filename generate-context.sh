#!/bin/bash

# generate-context.sh - Генератор AI-контекста проекта

set -e  # Останавливаем при ошибке

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Функция конвертации Windows UNC путей в WSL
convert_path() {
    local path="$1"
    if [[ "$path" =~ ^[^\\].*$ ]]; then
        echo "$path"
        return
    fi
    path="${path//\\//}"
    path=$(echo "$path" | sed 's|^/*wsl\$/[^/]*/|/|')
    echo "$path"
}

# Резолвим относительные пути от PROJECT_ROOT
resolve_path() {
    local path="$1"
    [ -z "$path" ] && echo "$path" && return
    [[ "$path" =~ ^/ ]] && echo "$path" && return
    echo "$PROJECT_ROOT/$path"
}

# Проверка флага --force
FORCE_MODE=false
if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

# Функция записи в JSON
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | sed ':a;N;$!ba;s/\n/\\n/g'
}

prompt_path() {
    local prompt_text="$1"
    local var_name="$2"
    local default_value="$3"
    local path_value

    if [ -n "$default_value" ] && [[ ! "$default_value" =~ ^[yYnN]$ ]]; then
        default_value=$(convert_path "$default_value")
    fi

    if [ -n "$default_value" ]; then
        echo -e "${BLUE}${prompt_text} [${default_value}]${NC}"
    else
        echo -e "${BLUE}${prompt_text}${NC}"
    fi
    echo -n "> "
    read -r path_value

    path_value=$(echo "$path_value" | xargs)

    if [ -z "$path_value" ] && [ -n "$default_value" ]; then
        path_value="$default_value"
    fi

    if [ -n "$path_value" ] && [[ ! "$path_value" =~ ^[yYnN]$ ]]; then
        path_value=$(convert_path "$path_value")
    fi

    eval "$var_name='$path_value'"
}

# Запрашиваем корень проекта
echo -e "${GREEN}=== AI Context Generator ===${NC}\n"

if [ -z "$PROJECT_ROOT" ]; then
    echo -e "${BLUE}Путь до корня проекта:${NC}"
    echo -e "${BLUE}(абсолютный путь, например: /opt/Projects/myapp):${NC}"
    echo -n "> "
    read -r PROJECT_ROOT_INPUT
    PROJECT_ROOT=$(convert_path "$PROJECT_ROOT_INPUT")
else
    PROJECT_ROOT=$(convert_path "$PROJECT_ROOT")
    echo -e "${GREEN}Используем PROJECT_ROOT: $PROJECT_ROOT${NC}\n"
fi

if [ ! -d "$PROJECT_ROOT" ]; then
    echo -e "${RED}⚠ Директория не найдена: $PROJECT_ROOT${NC}"
    exit 1
fi

cd "$PROJECT_ROOT" || exit 1

echo -e "${GREEN}✓ Работаем в: $(pwd)${NC}\n"

# Настройка путей
OUTPUT_DIR="$PROJECT_ROOT/.ai-context"
BACKEND_DIR="$OUTPUT_DIR/backend"
FRONTEND_DIR="$OUTPUT_DIR/frontend"
DATABASE_DIR="$OUTPUT_DIR/database"
CONFIG_FILE="$OUTPUT_DIR/.config"

mkdir -p "$BACKEND_DIR" "$FRONTEND_DIR" "$DATABASE_DIR"

# Загрузка сохраненной конфигурации
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    
    if [ "$FORCE_MODE" = false ]; then
        echo -e "${GREEN}Используем сохраненную конфигурацию${NC}"
        echo -e "${YELLOW}Для перенастройки используй --force${NC}\n"
        
        # Автоматический режим - используем все сохраненные значения
        SRC_PATH="$SAVED_SRC_PATH"
        FRONTEND_PATH="$SAVED_FRONTEND_PATH"
        MIGRATIONS_PATH="$SAVED_MIGRATIONS_PATH"
        OTHER_PATHS="$SAVED_OTHER_PATHS"
        NEED_DUMP="$SAVED_NEED_DUMP"
        DB_ENGINE="$SAVED_DB_ENGINE"
        DB_HOST="$SAVED_DB_HOST"
        DB_PORT="$SAVED_DB_PORT"
        DB_NAME="$SAVED_DB_NAME"
        DB_USER="$SAVED_DB_USER"
        DB_PASS="$SAVED_DB_PASS"
        
        SKIP_PROMPTS=true
    else
        echo -e "${YELLOW}Режим --force: перенастройка${NC}"
        echo "Указывайте относительные пути от корня проекта или абсолютные"
        echo "Оставьте пустым, если не нужно"
        echo ""
        SKIP_PROMPTS=false
    fi
else
    echo "Указывайте относительные пути от корня проекта или абсолютные"
    echo "Оставьте пустым, если не нужно"
    echo ""
    SKIP_PROMPTS=false
fi

# Запрашиваем пути только если не автоматический режим
if [ "$SKIP_PROMPTS" = false ]; then
    prompt_path "Путь до исходников (backend, например: src):" SRC_PATH "${SAVED_SRC_PATH:-}"
    prompt_path "Путь до фронтенда (например: src/angular):" FRONTEND_PATH "${SAVED_FRONTEND_PATH:-}"
    prompt_path "Путь до миграций (например: src/database/migrations):" MIGRATIONS_PATH "${SAVED_MIGRATIONS_PATH:-}"
    prompt_path "Другие важные файлы/директории (через запятую):" OTHER_PATHS "${SAVED_OTHER_PATHS:-}"

    echo ""
    echo -e "${BLUE}=== Database Settings ===${NC}"
    prompt_path "Нужен дамп базы? (y/n):" NEED_DUMP "${SAVED_NEED_DUMP:-}"

    if [ "$NEED_DUMP" = "y" ] || [ "$NEED_DUMP" = "Y" ]; then
        prompt_path "Движок БД (mysql/postgresql/mariadb):" DB_ENGINE "${SAVED_DB_ENGINE:-}"
        prompt_path "Хост:" DB_HOST "${SAVED_DB_HOST:-localhost}"
        prompt_path "Порт:" DB_PORT "${SAVED_DB_PORT:-3306}"
        prompt_path "Имя базы данных:" DB_NAME "${SAVED_DB_NAME:-}"
        prompt_path "Пользователь БД:" DB_USER "${SAVED_DB_USER:-root}"
        prompt_path "Пароль БД:" DB_PASS "${SAVED_DB_PASS:-}"
    fi
fi

# Резолвим пути
SRC_PATH=$(resolve_path "$SRC_PATH")
FRONTEND_PATH=$(resolve_path "$FRONTEND_PATH")
MIGRATIONS_PATH=$(resolve_path "$MIGRATIONS_PATH")

if [ -n "$OTHER_PATHS" ]; then
    IFS=',' read -ra PATHS_ARRAY <<< "$OTHER_PATHS"
    RESOLVED_PATHS=()
    for p in "${PATHS_ARRAY[@]}"; do
        p=$(echo "$p" | xargs)
        RESOLVED_PATHS+=("$(resolve_path "$p")")
    done
    OTHER_PATHS=$(IFS=','; echo "${RESOLVED_PATHS[*]}")
fi

# Показываем конфигурацию только если был запрос
if [ "$SKIP_PROMPTS" = false ]; then
    echo ""
    echo -e "${YELLOW}=== Сохраняемая конфигурация ===${NC}"
    echo "SRC_PATH: $SRC_PATH"
    echo "FRONTEND_PATH: $FRONTEND_PATH"
    echo "MIGRATIONS_PATH: $MIGRATIONS_PATH"
    echo "OTHER_PATHS: $OTHER_PATHS"
    echo "DB: $NEED_DUMP"
    if [ "$NEED_DUMP" = "y" ] || [ "$NEED_DUMP" = "Y" ]; then
        echo "DB_ENGINE: $DB_ENGINE"
        echo "DB_HOST: $DB_HOST"
        echo "DB_PORT: $DB_PORT"
        echo "DB_NAME: $DB_NAME"
        echo "DB_USER: $DB_USER"
    fi
    echo ""
    echo -e "${BLUE}Сохранить? (y/n):${NC}"
    read -r -n 1 CONFIRM
    echo ""
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo -e "${RED}Отменено${NC}"
        exit 0
    fi
fi

# Сохраняем конфигурацию
cat > "$CONFIG_FILE" << EOF
SAVED_SRC_PATH="$SRC_PATH"
SAVED_FRONTEND_PATH="$FRONTEND_PATH"
SAVED_MIGRATIONS_PATH="$MIGRATIONS_PATH"
SAVED_OTHER_PATHS="$OTHER_PATHS"
SAVED_NEED_DUMP="$NEED_DUMP"
SAVED_DB_ENGINE="$DB_ENGINE"
SAVED_DB_HOST="$DB_HOST"
SAVED_DB_PORT="$DB_PORT"
SAVED_DB_NAME="$DB_NAME"
SAVED_DB_USER="$DB_USER"
SAVED_DB_PASS="$DB_PASS"
EOF

echo -e "\n${GREEN}Генерация...${NC}\n"

# ========== PROJECT.JSON ==========
echo -e "${BLUE}Создание project.json...${NC}"

PROJECT_JSON="$OUTPUT_DIR/project.json"
cat > "$PROJECT_JSON" << 'JSONEOF'
{
  "generated": "",
  "project_root": "",
  "paths": {
    "backend": "",
    "frontend": "",
    "migrations": "",
    "other": []
  },
  "stack": {
    "backend": {},
    "frontend": {},
    "database": {}
  }
}
JSONEOF

# Заполняем метаданные
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
jq --arg ts "$TIMESTAMP" \
   --arg root "$PROJECT_ROOT" \
   --arg backend "$SRC_PATH" \
   --arg frontend "$FRONTEND_PATH" \
   --arg migrations "$MIGRATIONS_PATH" \
   '.generated = $ts | .project_root = $root | .paths.backend = $backend | .paths.frontend = $frontend | .paths.migrations = $migrations' \
   "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"

# Добавляем OTHER_PATHS
if [ -n "$OTHER_PATHS" ]; then
    IFS=',' read -ra PATHS <<< "$OTHER_PATHS"
    OTHER_JSON="["
    for i in "${!PATHS[@]}"; do
        [ $i -gt 0 ] && OTHER_JSON+=","
        OTHER_JSON+="\"${PATHS[$i]}\""
    done
    OTHER_JSON+="]"
    jq --argjson other "$OTHER_JSON" '.paths.other = $other' "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
fi

# Backend stack
COMPOSER_FILE=""
if [ -f "$PROJECT_ROOT/composer.json" ]; then
    COMPOSER_FILE="$PROJECT_ROOT/composer.json"
elif [ -n "$SRC_PATH" ] && [ -f "$SRC_PATH/composer.json" ]; then
    COMPOSER_FILE="$SRC_PATH/composer.json"
else
    COMPOSER_FILE=$(find "$PROJECT_ROOT" -name "composer.json" -type f -not -path "*/vendor/*" -not -path "*/node_modules/*" 2>/dev/null | head -1)
fi

if [ -n "$COMPOSER_FILE" ] && [ -f "$COMPOSER_FILE" ]; then
    PHP_VERSION=$(grep -o '"php": "[^"]*"' "$COMPOSER_FILE" | cut -d'"' -f4 || echo "unknown")
    COMPOSER_REL="${COMPOSER_FILE#$PROJECT_ROOT/}"

    # Определяем PHP фреймворк
    FRAMEWORK="Custom"
    if grep -q '"laravel/framework"' "$COMPOSER_FILE"; then
        FRAMEWORK="Laravel"
    elif grep -q '"laravel/lumen-framework"' "$COMPOSER_FILE"; then
        FRAMEWORK="Lumen"
    elif grep -q '"symfony/symfony"' "$COMPOSER_FILE" || grep -q '"symfony/framework-bundle"' "$COMPOSER_FILE"; then
        FRAMEWORK="Symfony"
    elif grep -q '"yiisoft/yii2"' "$COMPOSER_FILE"; then
        FRAMEWORK="Yii2"
    elif grep -q '"cakephp/cakephp"' "$COMPOSER_FILE"; then
        FRAMEWORK="CakePHP"
    elif grep -q '"codeigniter4/framework"' "$COMPOSER_FILE"; then
        FRAMEWORK="CodeIgniter"
    elif grep -q '"slim/slim"' "$COMPOSER_FILE"; then
        FRAMEWORK="Slim"
    fi

    jq --arg php "$PHP_VERSION" \
       --arg file "$COMPOSER_REL" \
       --arg fw "$FRAMEWORK" \
       '.stack.backend.php = $php | .stack.backend.composer_location = $file | .stack.backend.framework = $fw' \
       "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
fi

# Frontend stack
if [ -n "$FRONTEND_PATH" ] && [ -f "$FRONTEND_PATH/package.json" ]; then
    FRAMEWORK=""
    if grep -q '"react"' "$FRONTEND_PATH/package.json"; then
        FRAMEWORK="React"
    elif grep -q '"vue"' "$FRONTEND_PATH/package.json"; then
        FRAMEWORK="Vue"
    elif grep -q '"@angular/core"' "$FRONTEND_PATH/package.json"; then
        FRAMEWORK="Angular"
    elif grep -q '"next"' "$FRONTEND_PATH/package.json"; then
        FRAMEWORK="Next.js"
    elif grep -q '"nuxt"' "$FRONTEND_PATH/package.json"; then
        FRAMEWORK="Nuxt"
    fi

    if [ -n "$FRAMEWORK" ]; then
        jq --arg fw "$FRAMEWORK" '.stack.frontend.framework = $fw' "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
    fi
fi

# Database stack
if [ "$NEED_DUMP" = "y" ] || [ "$NEED_DUMP" = "Y" ]; then
    jq --arg engine "$DB_ENGINE" \
       --arg host "$DB_HOST" \
       --arg port "$DB_PORT" \
       --arg db "$DB_NAME" \
       '.stack.database.engine = $engine | .stack.database.host = $host | .stack.database.port = $port | .stack.database.name = $db' \
       "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
fi

echo -e "${GREEN}✓ project.json создан${NC}"

# ========== BACKEND ==========
if [ -n "$SRC_PATH" ] && [ -d "$SRC_PATH" ]; then
    echo -e "${BLUE}Генерация backend структуры...${NC}"

    # Structure
    BACKEND_STRUCTURE="$BACKEND_DIR/structure.json"
    EXCLUDE_DIRS="vendor,node_modules,cache,storage,var,runtime"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$SCRIPT_DIR/generate-structure-json.py" "$SRC_PATH" "$BACKEND_STRUCTURE" "php" "$EXCLUDE_DIRS"

    # Dependencies
    if [ -f "$PROJECT_ROOT/composer.json" ]; then
        BACKEND_DEPS="$BACKEND_DIR/dependencies.json"
        jq '.require // {}' "$PROJECT_ROOT/composer.json" > "$BACKEND_DEPS" 2>/dev/null || echo '{}' > "$BACKEND_DEPS"
    fi

    # Configs
    BACKEND_CONFIGS="$BACKEND_DIR/configs.json"
    echo "{" > "$BACKEND_CONFIGS"
    echo "  \"files\": [" >> "$BACKEND_CONFIGS"

    CONFIGS=()
    [ -f "$PROJECT_ROOT/composer.json" ] && CONFIGS+=("\"composer.json\"")
    [ -f "$PROJECT_ROOT/docker-compose.yml" ] && CONFIGS+=("\"docker-compose.yml\"")

    if [ -d "$PROJECT_ROOT/config" ]; then
        while IFS= read -r file; do
            CONFIGS+=("\"${file#$PROJECT_ROOT/}\"")
        done < <(find "$PROJECT_ROOT/config" -type f \( -name "*.php" -o -name "*.yml" \) 2>/dev/null)
    fi

    printf '%s\n' "${CONFIGS[@]}" | jq -R . | jq -s '.' | jq '{files: .}' > "$BACKEND_CONFIGS"

    echo "" >> "$BACKEND_CONFIGS"
    echo "  ]" >> "$BACKEND_CONFIGS"
    echo "}" >> "$BACKEND_CONFIGS"

    echo -e "${GREEN}✓ Backend структура создана${NC}"
fi

# ========== FRONTEND ==========
if [ -n "$FRONTEND_PATH" ] && [ -d "$FRONTEND_PATH" ]; then
    echo -e "${BLUE}Генерация frontend структуры...${NC}"

    # Structure
    FRONTEND_STRUCTURE="$FRONTEND_DIR/structure.json"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$SCRIPT_DIR/generate-structure-json.py" "$FRONTEND_PATH" "$FRONTEND_STRUCTURE" "js,jsx,ts,tsx,vue" "node_modules,dist,build,.next,.nuxt"

    # Dependencies
    if [ -f "$FRONTEND_PATH/package.json" ]; then
        FRONTEND_DEPS="$FRONTEND_DIR/dependencies.json"
        jq '.dependencies // {}' "$FRONTEND_PATH/package.json" > "$FRONTEND_DEPS" 2>/dev/null || echo '{}' > "$FRONTEND_DEPS"
    fi

    # Configs
    FRONTEND_CONFIGS="$FRONTEND_DIR/configs.json"
    echo "{" > "$FRONTEND_CONFIGS"
    echo "  \"files\": [" >> "$FRONTEND_CONFIGS"

    CONFIGS=()
    [ -f "$FRONTEND_PATH/package.json" ] && CONFIGS+=("\"package.json\"")
    [ -f "$FRONTEND_PATH/tsconfig.json" ] && CONFIGS+=("\"tsconfig.json\"")
    [ -f "$FRONTEND_PATH/vite.config.js" ] && CONFIGS+=("\"vite.config.js\"")
    [ -f "$FRONTEND_PATH/vite.config.ts" ] && CONFIGS+=("\"vite.config.ts\"")
    [ -f "$FRONTEND_PATH/webpack.config.js" ] && CONFIGS+=("\"webpack.config.js\"")
    [ -f "$FRONTEND_PATH/next.config.js" ] && CONFIGS+=("\"next.config.js\"")

    for i in "${!CONFIGS[@]}"; do
        [ $i -gt 0 ] && echo "," >> "$FRONTEND_CONFIGS"
        echo -n "    ${CONFIGS[$i]}" >> "$FRONTEND_CONFIGS"
    done

    echo "" >> "$FRONTEND_CONFIGS"
    echo "  ]" >> "$FRONTEND_CONFIGS"
    echo "}" >> "$FRONTEND_CONFIGS"

    echo -e "${GREEN}✓ Frontend структура создана${NC}"
fi

# ========== DATABASE ==========
if [ "$NEED_DUMP" = "y" ] || [ "$NEED_DUMP" = "Y" ]; then
    echo -e "${BLUE}Создание дампа БД...${NC}"

    DUMP_FILE="$DATABASE_DIR/schema.sql"

    case "$DB_ENGINE" in
        mysql|mariadb)
            MYSQL_PWD="$DB_PASS" mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" "$DB_NAME" \
                --no-data --skip-comments --skip-add-drop-table --skip-lock-tables --skip-triggers > "$DUMP_FILE" 2>&1
            ;;
        postgresql)
            PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" \
                --schema-only --no-owner --no-privileges > "$DUMP_FILE" 2>&1
            ;;
    esac

    if [ -f "$DUMP_FILE" ] && [ -s "$DUMP_FILE" ]; then
        echo -e "${GREEN}✓ Дамп создан${NC}"
    else
        echo -e "${RED}✗ Ошибка создания дампа${NC}"
    fi
fi

# Migrations
if [ -n "$MIGRATIONS_PATH" ] && [ -d "$MIGRATIONS_PATH" ]; then
    echo -e "${BLUE}Создание списка миграций...${NC}"
    MIGRATIONS_FILE="$DATABASE_DIR/migrations.txt"
    ls -1t "$MIGRATIONS_PATH" 2>/dev/null | head -15 > "$MIGRATIONS_FILE"
    MIGRATION_COUNT=$(ls -1 "$MIGRATIONS_PATH" 2>/dev/null | wc -l)
    echo -e "\nTotal: $MIGRATION_COUNT migrations" >> "$MIGRATIONS_FILE"
    echo -e "${GREEN}✓ Список миграций создан${NC}"
fi

# Итоги
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Генерация завершена${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Структура файлов:"
echo "  $OUTPUT_DIR/project.json"
[ -d "$BACKEND_DIR" ] && echo "  $BACKEND_DIR/"
[ -d "$FRONTEND_DIR" ] && echo "  $FRONTEND_DIR/"
[ -d "$DATABASE_DIR" ] && echo "  $DATABASE_DIR/"
echo ""
