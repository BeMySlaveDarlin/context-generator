#!/bin/bash

# generate-context-generic.sh - Универсальный генератор AI-контекста

set -e

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Конвертация путей
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

# Проверка флага --force
FORCE_MODE=false
if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

echo -e "${GREEN}=== Generic AI Context Generator ===${NC}\n"

# Получаем PROJECT_ROOT
if [ -z "$PROJECT_ROOT" ]; then
    echo -e "${BLUE}Путь до корня проекта:${NC}"
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
CONFIG_FILE="$OUTPUT_DIR/.config"

mkdir -p "$OUTPUT_DIR"

# Загрузка конфигурации
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"

    if [ "$FORCE_MODE" = false ]; then
        echo -e "${GREEN}Используем сохраненную конфигурацию${NC}"
        echo -e "${YELLOW}Для перенастройки используй --force${NC}\n"

        # Автоматический режим - используем все сохраненные значения
        PROJECT_TYPE="$SAVED_PROJECT_TYPE"
        PROJECT_DESC="$SAVED_PROJECT_DESC"
        IMPORTANT_DIRS="$SAVED_IMPORTANT_DIRS"
        IMPORTANT_FILES="$SAVED_IMPORTANT_FILES"

        SKIP_PROMPTS=true
    else
        echo -e "${YELLOW}Режим --force: перенастройка${NC}\n"
        SKIP_PROMPTS=false
    fi
else
    SKIP_PROMPTS=false
fi

# Запрашиваем параметры только если не автоматический режим
if [ "$SKIP_PROMPTS" = false ]; then
    # Определяем тип проекта автоматически
    PROJECT_TYPE="unknown"
    if [ -f "$PROJECT_ROOT/server.properties" ] || [ -f "$PROJECT_ROOT/eula.txt" ]; then
        PROJECT_TYPE="minecraft"
    elif [ -f "$PROJECT_ROOT/go.mod" ]; then
        PROJECT_TYPE="go"
    elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
        PROJECT_TYPE="rust"
    elif [ -f "$PROJECT_ROOT/requirements.txt" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
        PROJECT_TYPE="python"
    elif [ -f "$PROJECT_ROOT/pom.xml" ] || [ -f "$PROJECT_ROOT/build.gradle" ]; then
        PROJECT_TYPE="java"
    elif [ -f "$PROJECT_ROOT/package.json" ]; then
        PROJECT_TYPE="nodejs"
    fi

    echo -e "${BLUE}Определён тип проекта: ${PROJECT_TYPE}${NC}"
    echo -e "${BLUE}Если неверно, укажи: minecraft/go/rust/python/java/nodejs/other${NC}"
    echo -n "> "
    read -r USER_TYPE
    if [ -n "$USER_TYPE" ]; then
        PROJECT_TYPE="$USER_TYPE"
    fi

    # Универсальные параметры
    echo ""
    echo -e "${BLUE}Краткое описание проекта:${NC}"
    echo -n "> "
    read -r PROJECT_DESC

    echo -e "${BLUE}Важные директории (через запятую, например: config,plugins,mods):${NC}"
    echo -n "> "
    read -r IMPORTANT_DIRS

    echo -e "${BLUE}Важные файлы (через запятую):${NC}"
    echo -n "> "
    read -r IMPORTANT_FILES
fi

# Сохраняем конфигурацию
cat > "$CONFIG_FILE" << EOF
SAVED_PROJECT_TYPE="$PROJECT_TYPE"
SAVED_PROJECT_DESC="$PROJECT_DESC"
SAVED_IMPORTANT_DIRS="$IMPORTANT_DIRS"
SAVED_IMPORTANT_FILES="$IMPORTANT_FILES"
EOF

echo -e "\n${GREEN}Генерация...${NC}\n"

# ========== PROJECT.JSON ==========
PROJECT_JSON="$OUTPUT_DIR/project.json"

cat > "$PROJECT_JSON" << EOF
{
  "generated": "$(date '+%Y-%m-%d %H:%M:%S')",
  "project_root": "$PROJECT_ROOT",
  "project_type": "$PROJECT_TYPE",
  "description": "$PROJECT_DESC",
  "structure": {},
  "configs": [],
  "important_files": []
}
EOF

# ========== СТРУКТУРА ПРОЕКТА ==========
STRUCTURE_FILE="$OUTPUT_DIR/structure.txt"

echo "Полная структура проекта:" > "$STRUCTURE_FILE"
echo "=========================" >> "$STRUCTURE_FILE"
echo "" >> "$STRUCTURE_FILE"

if command -v tree &> /dev/null; then
    tree -I 'node_modules|.git|__pycache__|target|build|dist' "$PROJECT_ROOT" 2>/dev/null | \
    sed 's/├/|/g; s/└/`/g; s/─/-/g; s/│/|/g' >> "$STRUCTURE_FILE"
else
    find "$PROJECT_ROOT" -maxdepth 4 -type d | grep -v 'node_modules\|.git\|__pycache__' >> "$STRUCTURE_FILE"
fi

echo -e "${GREEN}✓ Структура создана${NC}"

# ========== ВАЖНЫЕ ДИРЕКТОРИИ ==========
if [ -n "$IMPORTANT_DIRS" ]; then
    echo -e "${BLUE}Анализ важных директорий...${NC}"

    IFS=',' read -ra DIRS <<< "$IMPORTANT_DIRS"
    for dir in "${DIRS[@]}"; do
        dir=$(echo "$dir" | xargs)
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            DIR_FILE="$OUTPUT_DIR/${dir//\//_}.txt"
            echo "Содержимое: $dir" > "$DIR_FILE"
            echo "==================" >> "$DIR_FILE"
            echo "" >> "$DIR_FILE"
            ls -lah "$PROJECT_ROOT/$dir" >> "$DIR_FILE" 2>/dev/null
            echo -e "${GREEN}✓ $dir${NC}"
        fi
    done
fi

# ========== ВАЖНЫЕ ФАЙЛЫ ==========
CONFIGS_DIR="$OUTPUT_DIR/configs"
mkdir -p "$CONFIGS_DIR"

if [ -n "$IMPORTANT_FILES" ]; then
    echo -e "${BLUE}Копирование важных файлов...${NC}"

    IFS=',' read -ra FILES <<< "$IMPORTANT_FILES"
    for file in "${FILES[@]}"; do
        file=$(echo "$file" | xargs)
        if [ -f "$PROJECT_ROOT/$file" ]; then
            cp "$PROJECT_ROOT/$file" "$CONFIGS_DIR/"
            echo -e "${GREEN}✓ $file${NC}"
        fi
    done
fi

# ========== СПЕЦИФИЧНЫЕ ДЛЯ ТИПА ==========
case "$PROJECT_TYPE" in
    minecraft)
        echo -e "${BLUE}Minecraft Server анализ...${NC}"

        # server.properties
        if [ -f "$PROJECT_ROOT/server.properties" ]; then
            cp "$PROJECT_ROOT/server.properties" "$CONFIGS_DIR/"
        fi

        # Плагины/моды
        if [ -d "$PROJECT_ROOT/plugins" ]; then
            ls -1 "$PROJECT_ROOT/plugins" | grep -E '\.jar$' > "$OUTPUT_DIR/plugins.txt"
            echo -e "${GREEN}✓ Список плагинов создан${NC}"
        fi

        if [ -d "$PROJECT_ROOT/mods" ]; then
            ls -1 "$PROJECT_ROOT/mods" | grep -E '\.jar$' > "$OUTPUT_DIR/mods.txt"
            echo -e "${GREEN}✓ Список модов создан${NC}"
        fi
        ;;

    python)
        echo -e "${BLUE}Python проект анализ...${NC}"

        if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
            cp "$PROJECT_ROOT/requirements.txt" "$CONFIGS_DIR/"
            jq -R . "$PROJECT_ROOT/requirements.txt" | jq -s '{dependencies: .}' > "$OUTPUT_DIR/dependencies.json"
        fi

        if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
            cp "$PROJECT_ROOT/pyproject.toml" "$CONFIGS_DIR/"
        fi

        # Python version
        if command -v python3 &> /dev/null; then
            PYTHON_VER=$(python3 --version 2>&1 | cut -d' ' -f2)
            jq --arg ver "$PYTHON_VER" '.python_version = $ver' "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
        fi
        ;;

    go)
        echo -e "${BLUE}Go проект анализ...${NC}"

        if [ -f "$PROJECT_ROOT/go.mod" ]; then
            cp "$PROJECT_ROOT/go.mod" "$CONFIGS_DIR/"
        fi

        if command -v go &> /dev/null; then
            GO_VER=$(go version | awk '{print $3}')
            jq --arg ver "$GO_VER" '.go_version = $ver' "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
        fi
        ;;

    rust)
        echo -e "${BLUE}Rust проект анализ...${NC}"

        if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
            cp "$PROJECT_ROOT/Cargo.toml" "$CONFIGS_DIR/"
        fi

        if command -v rustc &> /dev/null; then
            RUST_VER=$(rustc --version | awk '{print $2}')
            jq --arg ver "$RUST_VER" '.rust_version = $ver' "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
        fi
        ;;

    nodejs)
        echo -e "${BLUE}Node.js проект анализ...${NC}"

        if [ -f "$PROJECT_ROOT/package.json" ]; then
            cp "$PROJECT_ROOT/package.json" "$CONFIGS_DIR/"
            jq '{dependencies: .dependencies, devDependencies: .devDependencies}' "$PROJECT_ROOT/package.json" > "$OUTPUT_DIR/dependencies.json" 2>/dev/null
        fi

        if command -v node &> /dev/null; then
            NODE_VER=$(node --version)
            jq --arg ver "$NODE_VER" '.node_version = $ver' "$PROJECT_JSON" > "$PROJECT_JSON.tmp" && mv "$PROJECT_JSON.tmp" "$PROJECT_JSON"
        fi
        ;;
esac

# Итоги
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Генерация завершена${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Структура файлов:"
echo "  $OUTPUT_DIR/project.json"
echo "  $OUTPUT_DIR/structure.txt"
[ -d "$CONFIGS_DIR" ] && echo "  $CONFIGS_DIR/"
echo ""
echo "Используй файлы для загрузки в Claude"
