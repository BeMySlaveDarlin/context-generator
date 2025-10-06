# Makefile для генерации AI-контекста проектов

SCRIPT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
PHP_GENERATOR := $(SCRIPT_DIR)/generate-context.sh
GENERIC_GENERATOR := $(SCRIPT_DIR)/generate-context-generic.sh

# Подключаем локальные проекты если файл существует
-include Makefile.local

.PHONY: help
help:
	@echo "AI Context Generator"
	@echo ""
	@echo "Available commands:"
	@echo "  make new             - Add new project"
	@echo "  make list            - List all configured projects"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) Makefile.local 2>/dev/null | \
	   awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-15s - %s\n", $$1, $$2}'

.PHONY: new
new:
	@bash $(SCRIPT_DIR)/add-project.sh

.PHONY: list
list:
	@echo "Configured projects:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) Makefile.local 2>/dev/null | \
	   grep -v "^help:" | grep -v "^new:" | grep -v "^list:" | \
	   awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# Базовые примеры (опционально, можно удалить)
.PHONY: example
example: ## Example project
	@echo "Create Makefile.local for your projects"
