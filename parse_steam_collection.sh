#!/bin/bash

# ======================================================
# Скрипт для парсинга коллекций Steam Workshop
# Сохраняет каждую страницу мода в modhtml/<workshop_id>/index.html
# ======================================================
# Включить дебаг режим
DEBUG_MODE=0

# Функция для дебаг логирования
log_debug() {
    if [ $DEBUG_MODE -eq 1 ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

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

# Функция для извлечения всех Workshop ID из коллекции (только реальные предметы)
extract_workshop_ids_from_collection() {
    local html_file="$1"
    
    if [ ! -f "$html_file" ] || [ ! -s "$html_file" ]; then
        return 1
    fi
    
    local html=$(cat "$html_file" 2>/dev/null | tr -d '\000')
    local ids=()
    
    # Ищем элементы с классом collectionItem и извлекаем ID
    # Сначала ищем data-publishedfileid внутри collectionItem
    local ids1=$(echo "$html" | grep -oP 'class="collectionItem".*?data-publishedfileid="\K\d+' | sort -u 2>/dev/null)
    for id in $ids1; do
        [ -n "$id" ] && ids+=("$id")
    done
    
    # Если не нашли - ищем id="sharedfile_"
    if [ ${#ids[@]} -eq 0 ]; then
        local ids2=$(echo "$html" | grep -oP 'id="sharedfile_\K\d+' | sort -u 2>/dev/null)
        for id in $ids2; do
            [ -n "$id" ] && ids+=("$id")
        done
    fi
    
    # Если все еще пусто - ищем все data-publishedfileid (но только в контексте коллекции)
    if [ ${#ids[@]} -eq 0 ]; then
        # Ищем только те, что внутри collectionChildren
        local collection_html=$(echo "$html" | grep -oP '(?s)<div class="collectionChildren".*?</div>' | head -1)
        if [ -n "$collection_html" ]; then
            local ids3=$(echo "$collection_html" | grep -oP 'data-publishedfileid="\K\d+' | sort -u 2>/dev/null)
            for id in $ids3; do
                [ -n "$id" ] && ids+=("$id")
            done
        fi
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
    
    # Ищем блок с описанием мода
    local desc_block=$(echo "$html" | grep -oP '(?s)<div class="workshopItemDescription".*?>(.*?)</div>' | head -1)
    
    if [ -n "$desc_block" ]; then
        # Ищем все строки с "Mod ID:" в блоке описания
        # Формат: Mod ID: xxx (может быть несколько, включая пути типа 2256623447/firearmmod)
        local ids=$(echo "$desc_block" | grep -oP 'Mod ID:\s*\K[^\n<]+' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null)
        
        # Разбиваем каждую найденную строку на отдельные ID
        for entry in $ids; do
            # Если в строке есть запятые - разбиваем
            if echo "$entry" | grep -q ","; then
                echo "$entry" | sed 's/,/\n/g' | while read -r part; do
                    part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    [ -n "$part" ] && mod_ids+=("$part")
                done
            else
                [ -n "$entry" ] && mod_ids+=("$entry")
            fi
        done
        
        # Если ничего не нашли через "Mod ID:", ищем в конце описания
        if [ ${#mod_ids[@]} -eq 0 ]; then
            # Ищем строки, которые выглядят как "Mod ID:" но могут быть без двоеточия
            local ids2=$(echo "$desc_block" | grep -oP '(?i)mod id[: ]+\K[^\n<]+' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null)
            for entry in $ids2; do
                if echo "$entry" | grep -q ","; then
                    echo "$entry" | sed 's/,/\n/g' | while read -r part; do
                        part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        [ -n "$part" ] && mod_ids+=("$part")
                    done
                else
                    [ -n "$entry" ] && mod_ids+=("$entry")
                fi
            done
        fi
        
        # Если все еще ничего не нашли - пробуем искать в HTML, но только в контексте "Mod ID:"
        if [ ${#mod_ids[@]} -eq 0 ]; then
            local ids3=$(echo "$html" | grep -oP 'Mod ID:\s*\K[a-zA-Z0-9_/]+' | sort -u 2>/dev/null)
            for id in $ids3; do
                [ -n "$id" ] && mod_ids+=("$id")
            done
        fi
        
    else
        # Если блок описания не найден - ищем во всем HTML
        log_debug "  Блок workshopItemDescription НЕ найден, ищем во всем HTML"
        local ids4=$(echo "$html" | grep -oP 'Mod ID:\s*\K[a-zA-Z0-9_/]+' | sort -u 2>/dev/null)
        for id in $ids4; do
            [ -n "$id" ] && mod_ids+=("$id")
        done
        
        if [ ${#mod_ids[@]} -eq 0 ]; then
            local ids5=$(echo "$html" | grep -oP 'Mod ID:\s*<[^>]*>\K[a-zA-Z0-9_/]+' | sort -u 2>/dev/null)
            for id in $ids5; do
                [ -n "$id" ] && mod_ids+=("$id")
            done
        fi
    fi
    
    # Удаляем дубликаты
    if [ ${#mod_ids[@]} -gt 0 ]; then
        local unique_ids=()
        for id in "${mod_ids[@]}"; do
            local found=0
            for unique in "${unique_ids[@]}"; do
                if [ "$unique" == "$id" ]; then
                    found=1
                    break
                fi
            done
            if [ $found -eq 0 ]; then
                unique_ids+=("$id")
            fi
        done
        mod_ids=("${unique_ids[@]}")
    fi
    
    # Выводим результат
    echo "${mod_ids[@]}"
}
# Функция для загрузки/получения страницы мода
get_mod_page() {
    local workshop_id="$1"
    local mod_dir="$MOD_HTML_DIR/$workshop_id"
    local mod_file="$mod_dir/index.html"
    local was_cached=0
    
    mkdir -p "$mod_dir"
    
    # Проверяем, есть ли уже сохраненная страница
    if [ -f "$mod_file" ] && [ -s "$mod_file" ]; then
        log_info "  [CACHE] Используем кэш: $mod_file"
        CACHED_ITEMS=$((CACHED_ITEMS + 1))
        was_cached=1
        echo "$mod_file|$was_cached"
        return 0
    fi
    
    # Если режим только кэша - пропускаем
    if [ $CACHE_ONLY -eq 1 ]; then
        show_cache_only_error "$workshop_id"
        return 1
    fi
    
    # Если нет - скачиваем (с задержкой)
    log_info "  [DOWNLOAD] Загрузка мода $workshop_id..."
    sleep 3
    local mod_url="https://steamcommunity.com/sharedfiles/filedetails/?id=$workshop_id"
    
    if get_page_silent "$mod_url" "$mod_file"; then
        DOWNLOADED_ITEMS=$((DOWNLOADED_ITEMS + 1))
        was_cached=0
        echo "$mod_file|$was_cached"
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

# Функция для генерации docker-compose.yml
generate_docker_compose() {
    local workshop_ids="$1"
    local mod_ids="$2"
    local compose_file="../docker-compose.yml"
    
    # Проверяем, что есть данные
    if [ -z "$workshop_ids" ] || [ -z "$mod_ids" ]; then
        log_warn "Нет данных для генерации docker-compose.yml"
        return 1
    fi
    
    # Создаем директорию если её нет
    mkdir -p "$(dirname "$compose_file")"
    
    log_info "Генерация docker-compose.yml в $compose_file"
    
    cat > "$compose_file" << EOF
services:
  project-zomboid-server:
    image: danixu86/project-zomboid-dedicated-server:latest-unstable
    container_name: pz-server
    restart: unless-stopped
    ports:
      - "16261:16261/udp"
      - "16262:16262/udp"
      - "27015:27015/tcp"
    environment:
      - ADMINPASSWORD=giraffe
      - PASSWORD=diefast
      - PUBLIC=false
      - SERVERNAME=Martians
      - MEMORY=12288m
      - WORKSHOP_IDS=$workshop_ids
      - MOD_IDS=$mod_ids
    volumes:
      - ./server-data:/home/steam/Zomboid
      - ./mods_pz:/home/steam/pz-dedicated/steamapps
EOF
    
    if [ -f "$compose_file" ]; then
        log_success "docker-compose.yml создан: $compose_file"
    else
        log_error "Не удалось создать docker-compose.yml"
        return 1
    fi
}

# Функция для проверки и очистки кэша от лишних модов
cleanup_cache() {
    local collection_ids=("$@")
    
    if [ ! -d "$MOD_HTML_DIR" ]; then
        return 0
    fi
    
    log_info "Проверка кэша на наличие лишних модов..."
    
    local removed_count=0
    local kept_count=0
    
    # Создаем массив для быстрого поиска
    declare -A id_map
    for id in "${collection_ids[@]}"; do
        id_map["$id"]=1
    done
    
    # Проходим по всем папкам в modhtml
    for dir in "$MOD_HTML_DIR"/*/; do
        if [ -d "$dir" ]; then
            # Получаем имя папки (workshop_id)
            local dir_name=$(basename "$dir")
            
            # Пропускаем файлы коллекции
            if [[ "$dir_name" == collection_* ]]; then
                continue
            fi
            
            # Проверяем, есть ли этот ID в списке коллекции
            if [[ -z "${id_map[$dir_name]}" ]]; then
                # ID нет в коллекции - удаляем
                log_warn "  🗑️  Удаляем лишний кэш: $dir_name (не найден в коллекции)"
                rm -rf "$dir"
                removed_count=$((removed_count + 1))
            else
                kept_count=$((kept_count + 1))
            fi
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  📁  ОЧИСТКА КЭША                                         ${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  Удалено лишних папок: $removed_count${NC}"
        echo -e "${YELLOW}  Оставлено папок: $kept_count${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
    else
        log_info "Лишних модов в кэше не найдено"
        log_info "  Папок в кэше: $kept_count"
    fi
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
    
    # Извлекаем все Workshop ID из коллекции (только реальные предметы)
    local workshop_ids=($(extract_workshop_ids_from_collection "$collection_file"))
    
    if [ ${#workshop_ids[@]} -eq 0 ]; then
        log_error "Не найдено предметов в коллекции"
        return 1
    fi
    
    TOTAL_ITEMS=${#workshop_ids[@]}
    log_info "Найдено предметов в коллекции: $TOTAL_ITEMS"
    
    cleanup_cache "${workshop_ids[@]}"

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
            local mod_result=$(get_mod_page "$workshop_id")
            
            if [ -z "$mod_result" ]; then
                ERROR_COUNT=$((ERROR_COUNT + 1))
                log_warn "  [SKIP] Пропускаем мод $workshop_id (не удалось получить страницу)"
                continue
            fi
            
            # Разбираем результат: файл|был_в_кэше
            local mod_file="${mod_result%|*}"
            local was_cached="${mod_result#*|}"
            
            if [ -z "$mod_file" ] || [ ! -f "$mod_file" ]; then
                ERROR_COUNT=$((ERROR_COUNT + 1))
                log_warn "  [SKIP] Пропускаем мод $workshop_id (файл не найден)"
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
                result_mod_ids="\\\\$selected_mod_id"
            else
                result_mod_ids="$result_mod_ids;\\\\$selected_mod_id"
            fi
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
    
    echo "    - WORKSHOP_IDS=$result_workshop_ids"
    echo "    - MOD_IDS=$result_mod_ids"
    
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
        echo "    - WORKSHOP_IDS=$result_workshop_ids"
        echo "    - MOD_IDS=$result_mod_ids"
    } > "$result_file"

    # Генерируем docker-compose.yml
    generate_docker_compose "$result_workshop_ids" "$result_mod_ids"

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
        -d|--debug)
            DEBUG_MODE=1
            shift
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
