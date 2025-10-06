#!/bin/bash

# add-project.sh - Добавление нового проекта в Makefile

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAKEFILE="$SCRIPT_DIR/Makefile.local"
PHP_GENERATOR="$SCRIPT_DIR/generate-context.sh"
GENERIC_GENERATOR="$SCRIPT_DIR/generate-context-generic.sh"

# Функция конвертации Windows UNC путей в WSL
convert_path() {
    local path="$1"
    path="${path//\\//}"
    path=$(echo "$path" | sed 's|^/*wsl\$/[^/]*/|/|')
    echo "$path"
}

echo -e "${GREEN}=== Add New Project ===${NC}\n"

# Запрашиваем данные
echo -e "${BLUE}Название проекта (алиас для make, например: myapp):${NC}"
echo -n "> "
read -r PROJECT_NAME

# Валидация имени
if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Ошибка: название не может быть пустым${NC}"
    exit 1
fi

if ! [[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}Ошибка: используй только буквы, цифры, дефис и подчеркивание${NC}"
    exit 1
fi

# Проверяем, не существует ли уже
if grep -q "^${PROJECT_NAME}:.*##" "$MAKEFILE" 2>/dev/null; then
    echo -e "${YELLOW}Проект '$PROJECT_NAME' уже существует в Makefile${NC}"
    echo -e "${YELLOW}Хочешь перезаписать? (y/n):${NC}"
    read -r -n 1 REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено"
        exit 0
    fi
    # Удаляем старую запись
    sed -i "/^${PROJECT_NAME}:.*##/,/^${PROJECT_NAME}-force:/d" "$MAKEFILE"
fi

echo -e "${BLUE}Путь до корня проекта:${NC}"
echo -e "${BLUE}(можно использовать Windows UNC: \\\\wsl\$\\Debian\\opt\\Projects\\...):${NC}"
echo -n "> "
read -r PROJECT_ROOT_INPUT

# Конвертируем путь
PROJECT_ROOT=$(convert_path "$PROJECT_ROOT_INPUT")

echo -e "${GREEN}Исходный путь: $PROJECT_ROOT_INPUT${NC}"
echo -e "${GREEN}Преобразованный путь: $PROJECT_ROOT${NC}"

if [ ! -d "$PROJECT_ROOT" ]; then
    echo -e "${YELLOW}⚠ Директория не найдена: $PROJECT_ROOT${NC}"
    echo -e "${YELLOW}Продолжить? (y/n):${NC}"
    read -r -n 1 REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Выбор типа проекта
echo ""
echo -e "${BLUE}Тип проекта:${NC}"
echo "1) PHP/Web (Laravel, Symfony, etc)"
echo "2) Generic (Minecraft, Python, Go, Rust, etc)"
echo -n "> "
read -r PROJECT_TYPE_CHOICE

if [ "$PROJECT_TYPE_CHOICE" = "2" ]; then
    GENERATOR="$GENERIC_GENERATOR"
    PROJECT_TYPE_LABEL="generic"
else
    GENERATOR="$PHP_GENERATOR"
    PROJECT_TYPE_LABEL="php"
fi

echo -e "${BLUE}Краткое описание проекта (опционально):${NC}"
echo -n "> "
read -r PROJECT_DESC

if [ -z "$PROJECT_DESC" ]; then
    PROJECT_DESC="$PROJECT_ROOT"
fi

# Добавляем в Makefile
cat >> "$MAKEFILE" << EOF

.PHONY: ${PROJECT_NAME}
${PROJECT_NAME}: ## ${PROJECT_DESC}
	@PROJECT_ROOT="${PROJECT_ROOT}" \$(${PROJECT_TYPE_LABEL^^}_GENERATOR)

.PHONY: ${PROJECT_NAME}-force
${PROJECT_NAME}-force:
	@PROJECT_ROOT="${PROJECT_ROOT}" \$(${PROJECT_TYPE_LABEL^^}_GENERATOR) --force
EOF

echo -e "\n${GREEN}✓ Проект добавлен в Makefile${NC}"
echo -e "${GREEN}Тип: $PROJECT_TYPE_LABEL${NC}"
echo -e "${GREEN}Запусти генерацию: make ${PROJECT_NAME}${NC}\n"

# Сразу запускаем генерацию
echo -e "${BLUE}Запустить генерацию контекста сейчас? (y/n):${NC}"
read -r -n 1 REPLY
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    PROJECT_ROOT="$PROJECT_ROOT" "$GENERATOR"
fi
