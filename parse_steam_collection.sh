#!/bin/bash

# ======================================================
# Скрипт для парсинга коллекций Steam Workshop
# Сохраняет каждую страницу мода в modhtml/<workshop_id>/index.html
# ======================================================

# Конфигурация по умолчанию
CONFIG_FILE="config.yaml"
TEMP_DIR="/tmp/steam_parser_$$"
MOD_HTML_DIR="modhtml"
mkdir -p "$MOD_HTML_DIR" "$TEMP_DIR"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Счетчики
TOTAL_ITEMS=0
PROCESSED_ITEMS=0
CACHED_ITEMS=0
DOWNLOADED_ITEMS=0
WARN_COUNT=0
ERROR_COUNT=0
RATE_LIMIT=0

# Режимы
CACHE_ONLY=0  # 0 - обычный режим, 1 - только из кэша

# Функция для логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1" >&2
}

# Функция для вывода ошибки блокировки
show_rate_limit_error() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                                            ║${NC}"
    echo -e "${RED}║  🚫  ТЕБЯ ЗАБЛОЧИЛИ В STEAM ЛОШАРА =)                                     ║${NC}"
    echo -e "${RED}║                                                                            ║${NC}"
    echo -e "${RED}║  Steam временно ограничил количество запросов с вашего IP-адреса.          ║${NC}"
    echo -e "${RED}║                                                                            ║${NC}"
    echo -e "${RED}║  Рекомендации:                                                             ║${NC}"
    echo -e "${RED}║  1. Подождите 5-10 минут и попробуй снова                                  ║${NC}"
    echo -e "${RED}║  2. Используйте -t для парсинга только из кэша                             ║${NC}"
    echo -e "${RED}║  4. Используйте кэш (папка modhtml/) для повторных запусков                ║${NC}"
    echo -e "${RED}║                                                                            ║${NC}"
    echo -e "${RED}║  ❌  Парсинг прерван на предмете #$PROCESSED_ITEMS                        ║${NC}"
    echo -e "${RED}║                                                                            ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
}

# Функция для вывода ошибки при cache-only режиме
show_cache_only_error() {
    local workshop_id="$1"
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                                            ║${NC}"
    echo -e "${YELLOW}║  📁  РЕЖИМ КЭША (-t)                                                       ║${NC}"
    echo -e "${YELLOW}║                                                                            ║${NC}"
    echo -e "${YELLOW}║  Нет кэша для Workshop ID: $workshop_id                                    ║${NC}"
    echo -e "${YELLOW}║                                                                            ║${NC}"
    echo -e "${YELLOW}║  Для загрузки этого мода:                                                  ║${NC}"
    echo -e "${YELLOW}║  1. Запустите скрипт без -t для скачивания                                 ║${NC}"
    echo -e "${YELLOW}║  2. Или вручную сохраните страницу в:                                     ║${NC}"
    echo -e "${YELLOW}║     $MOD_HTML_DIR/$workshop_id/index.html                                  ║${NC}"
    echo -e "${YELLOW}║                                                                            ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    return 1
}

# Функция для получения HTML-страницы (silent mode) с проверкой на блокировку
get_page_silent() {
    local url="$1"
    local output_file="$2"
    local temp_output="$TEMP_DIR/temp_output.txt"
    
    # Выполняем запрос и сохраняем ответ
    local http_code=$(curl -s -L -o "$temp_output" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Accept-Language: en-US,en;q=0.9" \
        -H "Cache-Control: no-cache" \
        -w "%{http_code}" \
        "$url" 2>/dev/null)
    
    # Проверяем HTTP код
    if [ "$http_code" = "429" ] || [ "$http_code" = "403" ]; then
        RATE_LIMIT=1
        return 1
    fi
    
    if [ "$http_code" = "200" ] && [ -f "$temp_output" ] && [ -s "$temp_output" ]; then
        cp "$temp_output" "$output_file"
        return 0
    else
        return 1
    fi
}

# Функция для получения HTML-страницы коллекции
get_collection_page() {
    local url="$1"
    local output_file="$2"
    local temp_output="$TEMP_DIR/temp_collection.txt"
    
    sleep 3
    
    local http_code=$(curl -s -L -o "$temp_output" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        -H "Accept-Language: en-US,en;q=0.9" \
        -H "Cache-Control: no-cache" \
        -w "%{http_code}" \
        "$url" 2>/dev/null)
    
    if [ "$http_code" = "429" ] || [ "$http_code" = "403" ]; then
        RATE_LIMIT=1
        return 1
    fi
    
    if [ "$http_code" = "200" ] && [ -f "$temp_output" ] && [ -s "$temp_output" ]; then
        cp "$temp_output" "$output_file"
        return 0
    else
        return 1
    fi
}

# Функция для извлечения Workshop ID из URL
extract_workshop_id_from_url() {
    local url="$1"
    if [[ "$url" =~ id=([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Функция для извлечения всех Workshop ID из коллекции
extract_workshop_ids_from_collection() {
    local html_file="$1"
    
    if [ ! -f "$html_file" ] || [ ! -s "$html_file" ]; then
        return 1
    fi
    
    local html=$(cat "$html_file" 2>/dev/null | tr -d '\000')
    local ids=()
    
    # Метод 1: data-publishedfileid
    local ids1=$(echo "$html" | grep -oP 'data-publishedfileid="\K\d+' | sort -u 2>/dev/null)
    for id in $ids1; do
        [ -n "$id" ] && ids+=("$id")
    done
    
    # Метод 2: ссылки
    if [ ${#ids[@]} -eq 0 ]; then
        local ids2=$(echo "$html" | grep -oP 'href="https://steamcommunity.com/sharedfiles/filedetails/\?id=\d+"' | grep -oP 'id=\K\d+' | sort -u 2>/dev/null)
        for id in $ids2; do
            [ -n "$id" ] && ids+=("$id")
        done
    fi
    
    # Метод 3: JSON
    if [ ${#ids[@]} -eq 0 ]; then
        local ids3=$(echo "$html" | grep -oP '"publishedfileid":"\K\d+' | sort -u 2>/dev/null)
        for id in $ids3; do
            [ -n "$id" ] && ids+=("$id")
        done
    fi
    
    echo "${ids[@]}"
}

# Функция для извлечения Mod ID из HTML страницы мода
extract_mod_id_from_mod_page() {
    local html="$1"
    
    if [ -z "$html" ]; then
        echo ""
        return 1
    fi
    
    # Удаляем нулевые байты
    html=$(echo "$html" | tr -d '\000')
    
    local mod_ids=()
    
    # Ищем Mod ID в разных форматах
    # Формат 1: Mod ID: xxx (в тексте)
    local ids1=$(echo "$html" | grep -oP 'Mod ID:\s*\K[a-zA-Z0-9_]+' | sort -u 2>/dev/null)
    for id in $ids1; do
        [ -n "$id" ] && mod_ids+=("$id")
    done
    
    # Формат 2: Mod ID: xxx (с тегами)
    if [ ${#mod_ids[@]} -eq 0 ]; then
        local ids2=$(echo "$html" | grep -oP 'Mod ID:\s*<[^>]*>\K[a-zA-Z0-9_]+' | sort -u 2>/dev/null)
        for id in $ids2; do
            [ -n "$id" ] && mod_ids+=("$id")
        done
    fi
    
    # Формат 3: В JSON
    if [ ${#mod_ids[@]} -eq 0 ]; then
        local ids3=$(echo "$html" | grep -oP '"modid":"\K[a-zA-Z0-9_]+' | sort -u 2>/dev/null)
        for id in $ids3; do
            [ -n "$id" ] && mod_ids+=("$id")
        done
    fi
    
    # Формат 4: В описании (специфичные паттерны)
    if [ ${#mod_ids[@]} -eq 0 ]; then
        local ids4=$(echo "$html" | grep -oP 'damnlib|[A-Za-z]+[0-9_]+[A-Za-z]*' | sort -u 2>/dev/null)
        for id in $ids4; do
            [ -n "$id" ] && mod_ids+=("$id")
        done
    fi
    
    # Фильтруем мусорные ID (слишком короткие или подозрительные)
    local filtered_ids=()
    for id in "${mod_ids[@]}"; do
        # Пропускаем слишком короткие (меньше 3 символов)
        if [ ${#id} -lt 3 ]; then
            continue
        fi
        # Пропускаем подозрительные паттерны
        if [[ "$id" =~ ^[0-9]+$ ]] && [ ${#id} -lt 5 ]; then
            continue
        fi
        filtered_ids+=("$id")
    done
    
    # Если после фильтрации остались ID, используем их
    if [ ${#filtered_ids[@]} -gt 0 ]; then
        echo "${filtered_ids[@]}"
    else
        # Если все отфильтровались, но были оригинальные - возвращаем оригинальные
        echo "${mod_ids[@]}"
    fi
}

# Функция для загрузки/получения страницы мода
get_mod_page() {
    local workshop_id="$1"
    local mod_dir="$MOD_HTML_DIR/$workshop_id"
    local mod_file="$mod_dir/index.html"
    
    mkdir -p "$mod_dir"
    
    # Проверяем, есть ли уже сохраненная страница
    if [ -f "$mod_file" ] && [ -s "$mod_file" ]; then
        log_info "  [CACHE] Используем кэш: $mod_file"
        CACHED_ITEMS=$((CACHED_ITEMS + 1))
        echo "$mod_file"
        return 0
    fi
    
    # Если режим только кэша - пропускаем
    if [ $CACHE_ONLY -eq 1 ]; then
        show_cache_only_error "$workshop_id"
        return 1
    fi
    
    # Если нет - скачиваем
    log_info "  [DOWNLOAD] Загрузка мода $workshop_id..."
    local mod_url="https://steamcommunity.com/sharedfiles/filedetails/?id=$workshop_id"
    
    if get_page_silent "$mod_url" "$mod_file"; then
        DOWNLOADED_ITEMS=$((DOWNLOADED_ITEMS + 1))
        echo "$mod_file"
        return 0
    else
        if [ $RATE_LIMIT -eq 1 ]; then
            show_rate_limit_error
        fi
        log_warn "  [ERROR] Не удалось загрузить мод $workshop_id"
        return 1
    fi
}

# Функция для парсинга YAML конфигурации
parse_yaml_config() {
    local yaml_file="$1"
    local syncmod_file="$2"
    
    > "$syncmod_file"
    
    if [ ! -f "$yaml_file" ]; then
        return 1
    fi
    
    local collection_url=""
    
    # Извлекаем URL коллекции
    collection_url=$(grep -E '^[[:space:]]*collection:[[:space:]]*"' "$yaml_file" | \
        sed -E 's/^[[:space:]]*collection:[[:space:]]*"([^"]+)".*/\1/')
    
    if [ -z "$collection_url" ]; then
        collection_url=$(grep -E '^[[:space:]]*collection:[[:space:]]*' "$yaml_file" | \
            sed -E 's/^[[:space:]]*collection:[[:space:]]*(.*)/\1/' | sed 's/^"//;s/"$//')
    fi
    
    # Парсим syncmod
    local in_syncmod=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*syncmod:[[:space:]]*$ ]]; then
            in_syncmod=1
            continue
        fi
        
        if [ $in_syncmod -eq 1 ]; then
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z_]+:[[:space:]]*$ ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                in_syncmod=0
                continue
            fi
            
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([0-9]+)[[:space:]]*:[[:space:]]*[\"\047]?([a-zA-Z0-9_]+)[\"\047]? ]]; then
                echo "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}" >> "$syncmod_file"
            fi
        fi
    done < "$yaml_file"
    
    echo "$collection_url"
}

# Основная функция парсинга
parse_collection() {
    local collection_url="$1"
    local syncmod_file="$2"
    
    # Проверяем URL
    if [ -z "$collection_url" ]; then
        log_error "Не указан URL коллекции"
        return 1
    fi
    
    # Извлекаем ID коллекции
    local collection_id=$(extract_workshop_id_from_url "$collection_url")
    if [ -z "$collection_id" ]; then
        log_error "Не удалось извлечь ID коллекции из URL: $collection_url"
        return 1
    fi
    
    log_info "ID коллекции: $collection_id"
    
    # Проверяем наличие файла коллекции в кэше
    collection_file="$MOD_HTML_DIR/collection_$collection_id.html"
    
    if [ -f "$collection_file" ] && [ -s "$collection_file" ] && [ $CACHE_ONLY -eq 1 ]; then
        log_info "Используем кэш коллекции: $collection_file"
    elif [ $CACHE_ONLY -eq 1 ]; then
        log_error "Нет кэша коллекции. Запустите без -t для загрузки"
        return 1
    else
        # Загружаем страницу коллекции
        log_info "Загрузка коллекции: $collection_url"
        
        if ! get_collection_page "$collection_url" "$collection_file"; then
            if [ $RATE_LIMIT -eq 1 ]; then
                show_rate_limit_error
            fi
            log_error "Тебя заблокировали =) Жди и кайфуй"
            return 1
        fi
        log_success "Страница коллекции сохранена: $collection_file"
    fi
    
    # Извлекаем все Workshop ID из коллекции
    local workshop_ids=($(extract_workshop_ids_from_collection "$collection_file"))
    
    if [ ${#workshop_ids[@]} -eq 0 ]; then
        log_error "Не найдено предметов в коллекции"
        return 1
    fi
    
    TOTAL_ITEMS=${#workshop_ids[@]}
    log_info "Найдено предметов в коллекции: $TOTAL_ITEMS"
    
    # Загружаем syncmod
    declare -A syncmod_map
    if [ -f "$syncmod_file" ] && [ -s "$syncmod_file" ]; then
        while IFS='=' read -r workshop_id mod_id; do
            if [ -n "$workshop_id" ] && [ -n "$mod_id" ]; then
                syncmod_map["$workshop_id"]="$mod_id"
            fi
        done < "$syncmod_file"
        log_info "Загружено ${#syncmod_map[@]} правил синхронизации"
    fi
    
    # Массивы для результатов
    local result_workshop_ids=""
    local result_mod_ids=""
    
    # Обрабатываем каждый предмет
    local count=0
    for workshop_id in "${workshop_ids[@]}"; do
        count=$((count + 1))
        PROCESSED_ITEMS=$count
        
        echo -e "\n${BLUE}[$count/$TOTAL_ITEMS]${NC} Обработка Workshop ID: $workshop_id"
        
        # Проверяем syncmod
        local selected_mod_id=""
        if [[ -n "${syncmod_map[$workshop_id]}" ]]; then
            selected_mod_id="${syncmod_map[$workshop_id]}"
            log_info "  [SYNC] Используем syncmod: $selected_mod_id"
        else
            # Получаем страницу мода (из кэша или скачиваем)
            local mod_file=$(get_mod_page "$workshop_id")
            
            if [ -z "$mod_file" ] || [ ! -f "$mod_file" ]; then
                ERROR_COUNT=$((ERROR_COUNT + 1))
                log_warn "  [SKIP] Пропускаем мод $workshop_id (не удалось получить страницу)"
                continue
            fi
            
            # Читаем HTML страницы мода
            local mod_html=$(cat "$mod_file" 2>/dev/null | tr -d '\000')
            
            # Извлекаем все Mod ID
            local all_mod_ids=($(extract_mod_id_from_mod_page "$mod_html"))
            
            if [ ${#all_mod_ids[@]} -eq 0 ]; then
                log_warn "  [WARN] Mod ID не найден для Workshop ID: $workshop_id"
                selected_mod_id="unknown"
            elif [ ${#all_mod_ids[@]} -eq 1 ]; then
                selected_mod_id="${all_mod_ids[0]}"
                log_info "  [OK] Найден Mod ID: $selected_mod_id"
            else
                # Несколько Mod ID
                WARN_COUNT=$((WARN_COUNT + 1))
                log_warn "  [WARN] Обнаружено несколько Mod ID для Workshop ID: $workshop_id"
                for mod_id in "${all_mod_ids[@]}"; do
                    log_warn "    - $mod_id"
                done
                log_warn "  [WARN] Используется первый: ${all_mod_ids[0]}"
                log_warn "  [WARN] Рекомендуется добавить в syncmod:"
                log_warn "    - $workshop_id : \"${all_mod_ids[0]}\""
                selected_mod_id="${all_mod_ids[0]}"
            fi
        fi
        
        # Добавляем в результаты
        if [ -n "$workshop_id" ]; then
            if [ -z "$result_workshop_ids" ]; then
                result_workshop_ids="$workshop_id"
            else
                result_workshop_ids="$result_workshop_ids;$workshop_id"
            fi
        fi
        
        if [ -n "$selected_mod_id" ] && [ "$selected_mod_id" != "unknown" ]; then
            if [ -z "$result_mod_ids" ]; then
                result_mod_ids="\\$selected_mod_id"
            else
                result_mod_ids="$result_mod_ids;\\$selected_mod_id"
            fi
        fi
        
        # Небольшая задержка между запросами (если скачиваем новые)
        if [ ! -f "$MOD_HTML_DIR/$workshop_id/index.html" ] && [ $CACHE_ONLY -eq 0 ]; then
            sleep 0.5
        fi
    done
    
    # Добавляем точку с запятой в конце
    [ -n "$result_workshop_ids" ] && result_workshop_ids="$result_workshop_ids;"
    [ -n "$result_mod_ids" ] && result_mod_ids="$result_mod_ids;"
    
    # Выводим результаты
    echo ""
    echo -e "${GREEN}================================"
    echo -e "Результаты парсинга"
    echo -e "================================${NC}"
    
    if [ $WARN_COUNT -gt 0 ]; then
        echo -e "${YELLOW}ВНИМАНИЕ: Обнаружено $WARN_COUNT предметов с несколькими Mod ID${NC}"
        echo -e "${YELLOW}Рекомендуется добавить их в секцию syncmod в конфигурационном файле${NC}"
        echo ""
    fi
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "${YELLOW}ОШИБОК: $ERROR_COUNT предметов не удалось обработать${NC}"
        echo ""
    fi
    
    if [ $CACHE_ONLY -eq 1 ]; then
        echo -e "${CYAN}[РЕЖИМ КЭША] Использованы только локальные файлы${NC}"
        echo ""
    fi
    
    echo "WORKSHOP_IDS=$result_workshop_ids"
    echo "MOD_IDS=$result_mod_ids"
    
    # Статистика
    echo ""
    echo -e "${BLUE}Статистика:${NC}"
    echo "- Всего предметов в коллекции: $TOTAL_ITEMS"
    echo "- Успешно обработано: $PROCESSED_ITEMS"
    echo "- Использовано кэша: $CACHED_ITEMS"
    if [ $CACHE_ONLY -eq 0 ]; then
        echo "- Скачано новых: $DOWNLOADED_ITEMS"
    else
        echo "- Режим: ТОЛЬКО КЭШ (скачивание отключено)"
    fi
    echo "- Использовано syncmod: ${#syncmod_map[@]}"
    echo "- Предупреждений (несколько Mod ID): $WARN_COUNT"
    echo "- Ошибок загрузки: $ERROR_COUNT"
    echo "- Папка с HTML модов: $MOD_HTML_DIR/"
    
    # Сохраняем результаты в файл
    local result_file="result.txt"
    {
        echo "WORKSHOP_IDS=$result_workshop_ids"
        echo "MOD_IDS=$result_mod_ids"
        echo ""
        echo "# Статистика"
        echo "# Всего предметов в коллекции: $TOTAL_ITEMS"
        echo "# Успешно обработано: $PROCESSED_ITEMS"
        echo "# Использовано кэша: $CACHED_ITEMS"
        if [ $CACHE_ONLY -eq 0 ]; then
            echo "# Скачано новых: $DOWNLOADED_ITEMS"
        else
            echo "# Режим: ТОЛЬКО КЭШ"
        fi
        echo "# Использовано syncmod: ${#syncmod_map[@]}"
        echo "# Предупреждений: $WARN_COUNT"
        echo "# Ошибок загрузки: $ERROR_COUNT"
        echo "# Папка с HTML: $MOD_HTML_DIR/"
    } > "$result_file"
    
    log_success "Результаты сохранены в: $result_file"
}

# Функция создания примера конфигурации
create_example_config() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << 'EOF'
# Конфигурация парсинга коллекции Steam Workshop
# 
# Формат:
#   collection: "URL коллекции"
#   syncmod:
#     - WORKSHOP_ID: "Mod_ID"
#     - WORKSHOP_ID: "Mod_ID"
#
# Пример:

collection: "https://steamcommunity.com/sharedfiles/filedetails/?id=3751011995"

# Синхронизация Mod ID для предметов с несколькими вариантами
# Используйте, если для одного Workshop ID существует несколько Mod ID
syncmod:
  - 2761200458 : "YakiHS"
  - 3171167894 : "damnlib"
EOF
        log_success "Создан пример конфигурации: $config_file"
    else
        log_info "Конфигурационный файл уже существует: $config_file"
    fi
}

# Функция очистки кэша
clean_cache() {
    if [ -d "$MOD_HTML_DIR" ]; then
        log_info "Очистка кэша в $MOD_HTML_DIR/"
        rm -rf "$MOD_HTML_DIR"/*
        log_success "Кэш очищен"
    fi
}

# Функция отображения справки
show_help() {
    cat << 'EOF'
Использование: ./parse_steam_collection.sh [ОПЦИИ] [КОНФИГ]

Опции:
  -c, --config FILE    Использовать указанный конфигурационный файл
  -u, --url URL        Использовать указанный URL коллекции
  -t, --cache-only     Использовать ТОЛЬКО кэш (не скачивать новые страницы)
  -g, --generate       Сгенерировать пример конфигурационного файла
  -C, --clean          Очистить кэш (папку modhtml/)
  -h, --help           Показать эту справку

Режимы:
  Обычный режим        - скачивает недостающие страницы, использует кэш
  Кэш-режим (-t)      - использует ТОЛЬКО сохраненные страницы в modhtml/

Структура кэша:
  modhtml/
    ├── collection_<id>.html
    └── <workshop_id>/
        └── index.html

Примеры:
  # Обычный режим - скачивает недостающее
  ./parse_steam_collection.sh -c config.yaml
  
  # Только из кэша (быстро, без запросов к Steam)
  ./parse_steam_collection.sh -c config.yaml -t
  
  # С указанием URL в кэш-режиме
  ./parse_steam_collection.sh -u https://steamcommunity.com/sharedfiles/filedetails/?id=3751011995 -t
  
  # Очистка кэша
  ./parse_steam_collection.sh -C
EOF
}

# ======================================================
# Основная логика скрипта
# ======================================================

# Проверка наличия curl
if ! command -v curl &> /dev/null; then
    log_error "Требуется установленный curl"
    exit 1
fi

# Парсинг аргументов командной строки
CONFIG_FILE=""
COLLECTION_URL=""
GENERATE_CONFIG=0
CLEAN_CACHE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -u|--url)
            COLLECTION_URL="$2"
            shift 2
            ;;
        -t|--cache-only)
            CACHE_ONLY=1
            shift
            ;;
        -g|--generate)
            GENERATE_CONFIG=1
            shift
            ;;
        -C|--clean)
            CLEAN_CACHE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -f "$1" ]]; then
                CONFIG_FILE="$1"
                shift
            else
                log_error "Неизвестный аргумент: $1"
                show_help
                exit 1
            fi
            ;;
    esac
done

# Генерация примера конфигурации
if [ $GENERATE_CONFIG -eq 1 ]; then
    if [ -z "$CONFIG_FILE" ]; then
        CONFIG_FILE="config.yaml"
    fi
    create_example_config "$CONFIG_FILE"
    exit 0
fi

# Очистка кэша
if [ $CLEAN_CACHE -eq 1 ]; then
    clean_cache
    # Если только очистка - выходим
    if [ -z "$CONFIG_FILE" ] && [ -z "$COLLECTION_URL" ]; then
        exit 0
    fi
fi

# Определяем конфигурационный файл
if [ -z "$CONFIG_FILE" ] && [ -f "config.yaml" ]; then
    CONFIG_FILE="config.yaml"
fi

# Загружаем конфигурацию
SYNC_MOD_FILE="$TEMP_DIR/syncmod.txt"

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    log_info "Загрузка конфигурации из: $CONFIG_FILE"
    
    config_url=$(parse_yaml_config "$CONFIG_FILE" "$SYNC_MOD_FILE")
    if [ -n "$config_url" ] && [ -z "$COLLECTION_URL" ]; then
        COLLECTION_URL="$config_url"
        log_info "URL коллекции из конфига: $COLLECTION_URL"
    fi
    
    if [ -s "$SYNC_MOD_FILE" ]; then
        log_info "Загружено $(wc -l < "$SYNC_MOD_FILE") правил синхронизации"
    fi
else
    > "$SYNC_MOD_FILE"
fi

# Проверяем наличие URL
if [ -z "$COLLECTION_URL" ]; then
    log_error "Не указан URL коллекции. Используйте -u или укажите в config.yaml"
    show_help
    exit 1
fi

# Вывод режима работы
if [ $CACHE_ONLY -eq 1 ]; then
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  РЕЖИМ ТОЛЬКО КЭШ (-t) - скачивание отключено                ${NC}"
    echo -e "${CYAN}  Используются только файлы из папки: $MOD_HTML_DIR/          ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
fi

# Запуск парсинга
parse_collection "$COLLECTION_URL" "$SYNC_MOD_FILE"

# Очистка временных файлов (опционально)
# rm -rf "$TEMP_DIR"