#!/bin/bash

# Сборка и запуск парсера Steam Workshop

VENV_DIR="venv"
REQ_FILE="requirements.txt"
SCRIPT="parse.py"

# Создаем виртуальное окружение если его нет
if [ ! -d "$VENV_DIR" ]; then
    echo "Создание виртуального окружения..."
    python3 -m venv "$VENV_DIR"
fi

# Активируем и устанавливаем зависимости
source "$VENV_DIR/bin/activate"

if [ -f "$REQ_FILE" ]; then
    echo "Установка зависимостей..."
    pip install -r "$REQ_FILE" -q
fi

# Запускаем скрипт с переданными аргументами
python "$SCRIPT" "$@"