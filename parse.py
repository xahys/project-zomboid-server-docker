#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Парсер коллекций Steam Workshop
Полностью на Python с использованием BeautifulSoup
"""

import sys
import os
import re
import time
import json
import shutil
import argparse
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from typing import List, Dict, Set, Optional, Tuple
import requests
from bs4 import BeautifulSoup
import yaml

# ----------------------------------------------------------------------
# Конфигурация
DEFAULT_CONFIG = "config.yaml"
MOD_HTML_DIR = Path("modhtml")
TEMP_DIR = Path("/tmp/steam_parser_py")
# ----------------------------------------------------------------------
# Цвета для вывода (ANSI)
COLORS = {
    'RED': '\033[0;31m',
    'GREEN': '\033[0;32m',
    'YELLOW': '\033[1;33m',
    'BLUE': '\033[0;34m',
    'CYAN': '\033[0;36m',
    'MAGENTA': '\033[0;35m',
    'NC': '\033[0m'
}

def colorize(text, color):
    return f"{COLORS.get(color, '')}{text}{COLORS['NC']}"

# ----------------------------------------------------------------------
# Логирование
class Logger:
    def __init__(self, debug=False):
        self.debug_mode = debug

    def info(self, msg):
        print(colorize("[INFO]", 'BLUE'), msg)

    def success(self, msg):
        print(colorize("[SUCCESS]", 'GREEN'), msg)

    def warn(self, msg):
        print(colorize("[WARN]", 'YELLOW'), msg)

    def error(self, msg):
        print(colorize("[ERROR]", 'RED'), msg)

    def debug(self, msg):
        if self.debug_mode:
            print(colorize("[DEBUG]", 'CYAN'), msg)

# ----------------------------------------------------------------------
# Вспомогательные функции
def extract_workshop_id_from_url(url: str) -> Optional[str]:
    parsed = urlparse(url)
    qs = parse_qs(parsed.query)
    return qs.get('id', [None])[0]

def ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------------
# Класс для работы с кэшем страниц
class PageCache:
    def __init__(self, cache_dir: Path, logger: Logger):
        self.cache_dir = cache_dir
        self.logger = logger
        ensure_dir(cache_dir)

    def _get_cache_file(self, workshop_id: str) -> Path:
        """Получить путь к файлу кэша для workshop_id"""
        return self.cache_dir / workshop_id / "index.html"

    def get(self, workshop_id: str) -> Optional[str]:
        """Вернуть содержимое страницы из кэша, если есть"""
        if not workshop_id:
            return None
        cache_file = self._get_cache_file(workshop_id)
        if cache_file.exists():
            self.logger.info(f"  [CACHE] Используем кэш: {cache_file}")
            with open(cache_file, 'r', encoding='utf-8') as f:
                return f.read()
        return None

    def put(self, workshop_id: str, content: str):
        """Сохранить страницу в кэш"""
        if workshop_id:
            cache_file = self._get_cache_file(workshop_id)
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            with open(cache_file, 'w', encoding='utf-8') as f:
                f.write(content)

    def delete_extra(self, valid_ids: Set[str]):
        """Удалить папки/файлы кэша, которых нет в valid_ids"""
        removed = 0
        kept = 0
        for item in self.cache_dir.iterdir():
            if item.is_dir():
                dir_name = item.name
                if dir_name in valid_ids:
                    kept += 1
                else:
                    self.logger.warn(f"  🗑️  Удаляем лишний кэш: {dir_name} (не найден в коллекции)")
                    shutil.rmtree(item)
                    removed += 1
        return removed, kept

    def get_collection_file(self, collection_id: str) -> Path:
        """Получить путь к файлу коллекции"""
        return self.cache_dir / f"collection_{collection_id}.html"

    def save_collection(self, collection_id: str, content: str):
        """Сохранить страницу коллекции"""
        cache_file = self.get_collection_file(collection_id)
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        with open(cache_file, 'w', encoding='utf-8') as f:
            f.write(content)

    def get_collection(self, collection_id: str) -> Optional[str]:
        """Получить страницу коллекции из кэша"""
        cache_file = self.get_collection_file(collection_id)
        if cache_file.exists():
            self.logger.info(f"  [CACHE] Используем кэш коллекции: {cache_file}")
            with open(cache_file, 'r', encoding='utf-8') as f:
                return f.read()
        return None

# ----------------------------------------------------------------------
# Парсинг HTML
def parse_workshop_ids_from_collection(html: str) -> List[str]:
    soup = BeautifulSoup(html, 'html.parser')
    ids = []
    for item in soup.find_all('div', class_='collectionItem'):
        if item.has_attr('data-publishedfileid'):
            ids.append(item['data-publishedfileid'])
        else:
            link = item.find('a', href=re.compile(r'/sharedfiles/filedetails/\?id=\d+'))
            if link:
                href = link.get('href')
                m = re.search(r'id=(\d+)', href)
                if m:
                    ids.append(m.group(1))
    # Уникализация с сохранением порядка
    seen = set()
    return [x for x in ids if not (x in seen or seen.add(x))]



def parse_mod_ids_from_mod_page(html: str, debug: bool = False) -> List[str]:
    soup = BeautifulSoup(html, 'html.parser')
    
    if debug:
        print(colorize("[DEBUG] Начинаем парсинг Mod ID", 'CYAN'))
    
    # Ищем блок описания по ID или классу
    desc_div = soup.find('div', id='highlightContent')
    if debug:
        print(colorize(f"[DEBUG] Поиск по id='highlightContent': {'найдено' if desc_div else 'не найдено'}", 'CYAN'))
    
    if not desc_div:
        desc_div = soup.find('div', class_='workshopItemDescription')
        if debug:
            print(colorize(f"[DEBUG] Поиск по class='workshopItemDescription': {'найдено' if desc_div else 'не найдено'}", 'CYAN'))
    
    # Если блок не найден, ищем напрямую в HTML
    ids = []
    
    if desc_div:
        if debug:
            print(colorize(f"[DEBUG] Найден блок описания: tag={desc_div.name}, id={desc_div.get('id', '')}, class={desc_div.get('class', [])}", 'CYAN'))
        
        # Метод 1: Поиск через get_text()
        text = desc_div.get_text(separator='\n')
        if debug:
            print(colorize(f"[DEBUG] Полный текст блока:\n{text}", 'CYAN'))
        
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            m = re.search(r'Mod ID:\s*(.+)', line, re.IGNORECASE)
            if m:
                mod_id_part = m.group(1).strip()
                if debug:
                    print(colorize(f"[DEBUG] Найдено через get_text(): '{mod_id_part}'", 'CYAN'))
                if ',' in mod_id_part:
                    ids.extend([p.strip() for p in mod_id_part.split(',') if p.strip()])
                else:
                    ids.append(mod_id_part)
        
        # Метод 2: Если не нашли через get_text(), ищем напрямую в HTML
        if not ids:
            if debug:
                print(colorize("[DEBUG] Не найдено через get_text(), пробуем прямой поиск в HTML", 'CYAN'))
            
            # Ищем паттерн Mod ID: в HTML с помощью регулярного выражения
            html_str = str(desc_div)
            pattern = r'Mod ID:\s*<[^>]*>\s*([^<]+)'
            matches = re.findall(pattern, html_str, re.IGNORECASE)
            
            if not matches:
                # Альтернативный паттерн без тегов
                pattern2 = r'Mod ID:\s*([^\n<]+)'
                matches = re.findall(pattern2, html_str, re.IGNORECASE)
            
            if debug:
                print(colorize(f"[DEBUG] Найдено через regexp: {matches}", 'CYAN'))
            
            for mod_id_part in matches:
                mod_id_part = mod_id_part.strip()
                if mod_id_part:
                    if ',' in mod_id_part:
                        ids.extend([p.strip() for p in mod_id_part.split(',') if p.strip()])
                    else:
                        ids.append(mod_id_part)
        
        # Метод 3: Прямой поиск по тегам <b>Mod ID:</b>
        if not ids:
            if debug:
                print(colorize("[DEBUG] Пробуем поиск по тегам", 'CYAN'))
            # Ищем все теги <b> с текстом "Mod ID:"
            for b_tag in desc_div.find_all('b'):
                if b_tag.get_text() and 'Mod ID:' in b_tag.get_text():
                    # Ищем следующий элемент за тегом
                    next_sibling = b_tag.next_sibling
                    if next_sibling and isinstance(next_sibling, str):
                        mod_id_part = next_sibling.strip()
                        if mod_id_part:
                            if debug:
                                print(colorize(f"[DEBUG] Найдено через тег <b>: '{mod_id_part}'", 'CYAN'))
                            if ',' in mod_id_part:
                                ids.extend([p.strip() for p in mod_id_part.split(',') if p.strip()])
                            else:
                                ids.append(mod_id_part)
                    else:
                        # Может быть следующий тег
                        next_tag = b_tag.find_next_sibling()
                        if next_tag and next_tag.name == 'b':
                            mod_id_part = next_tag.get_text().strip()
                            if mod_id_part:
                                if debug:
                                    print(colorize(f"[DEBUG] Найдено через тег <b> (следующий тег): '{mod_id_part}'", 'CYAN'))
                                if ',' in mod_id_part:
                                    ids.extend([p.strip() for p in mod_id_part.split(',') if p.strip()])
                                else:
                                    ids.append(mod_id_part)
    
    # Если ничего не нашли через BeautifulSoup, ищем напрямую в HTML строке
    if not ids:
        if debug:
            print(colorize("[DEBUG] Пробуем поиск напрямую в HTML строке", 'CYAN'))
        # Ищем все вхождения Mod ID: в HTML
        pattern = r'Mod ID:\s*</?b>\s*([^<]+)'
        matches = re.findall(pattern, html, re.IGNORECASE)
        if debug:
            print(colorize(f"[DEBUG] Найдено через прямой поиск в HTML: {matches}", 'CYAN'))
        for mod_id_part in matches:
            mod_id_part = mod_id_part.strip()
            if mod_id_part:
                if ',' in mod_id_part:
                    ids.extend([p.strip() for p in mod_id_part.split(',') if p.strip()])
                else:
                    ids.append(mod_id_part)
    
    # Уникализация с сохранением порядка
    seen = set()
    unique = [x for x in ids if not (x in seen or seen.add(x))]
    
    if debug:
        print(colorize(f"[DEBUG] Найдено уникальных Mod ID: {len(unique)}", 'CYAN'))
        if unique:
            for idx, uid in enumerate(unique, 1):
                print(colorize(f"[DEBUG]   #{idx}: '{uid}'", 'CYAN'))
        else:
            # Выводим часть HTML для отладки
            debug_snippet = html[:1000] if len(html) > 1000 else html
            print(colorize(f"[DEBUG] HTML (первые 1000 символов):\n{debug_snippet}", 'CYAN'))
    
    return unique



# ----------------------------------------------------------------------
# Загрузка страниц с задержками и обработкой ошибок
def fetch_page(url: str, cache: PageCache, logger: Logger, force_refresh: bool = False) -> Optional[str]:
    workshop_id = extract_workshop_id_from_url(url)
    
    # Проверяем кэш
    if not force_refresh:
        cached = cache.get(workshop_id)
        if cached:
            return cached

    # Если только кэш — не загружаем
    if hasattr(cache, 'only_cache') and cache.only_cache:
        logger.error(f"  Нет кэша для Workshop ID: {workshop_id} (режим --cache-only)")
        return None

    logger.info(f"  [DOWNLOAD] Загрузка мода {workshop_id}...")
    time.sleep(3)  # задержка между запросами
    try:
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}
        resp = requests.get(url, headers=headers, timeout=30)
        if resp.status_code == 429 or resp.status_code == 403:
            logger.error(f"  Блокировка (HTTP {resp.status_code})")
            print()
            print(colorize("╔═══════════════════════════════════════════════════════════════════════════╗", 'RED'))
            print(colorize("║  🚫  ТЕБЯ ЗАБЛОЧИЛИ В STEAM ЛОШАРА =)                                     ║", 'RED'))
            print(colorize("║  Steam временно ограничил количество запросов с вашего IP-адреса.          ║", 'RED'))
            print(colorize("║  Рекомендации:                                                             ║", 'RED'))
            print(colorize("║  1. Подождите 5-10 минут и попробуй снова                                  ║", 'RED'))
            print(colorize("║  2. Используйте -t для парсинга только из кэша                             ║", 'RED'))
            print(colorize("║  3. Используйте кэш (папка modhtml/) для повторных запусков                ║", 'RED'))
            print(colorize("╚═══════════════════════════════════════════════════════════════════════════╝", 'RED'))
            sys.exit(1)
        resp.raise_for_status()
        cache.put(workshop_id, resp.text)
        return resp.text
    except requests.exceptions.RequestException as e:
        logger.error(f"  Ошибка загрузки: {e}")
        return None

def fetch_collection_page(url: str, cache: PageCache, logger: Logger) -> Optional[str]:
    collection_id = extract_workshop_id_from_url(url)
    
    # Проверяем кэш
    cached = cache.get_collection(collection_id)
    if cached:
        return cached
    
    # Если только кэш — не загружаем
    if hasattr(cache, 'only_cache') and cache.only_cache:
        logger.error(f"Нет кэша коллекции (режим --cache-only)")
        return None
    
    logger.info(f"Загрузка коллекции: {url}")
    time.sleep(3)
    try:
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}
        resp = requests.get(url, headers=headers, timeout=30)
        if resp.status_code == 429 or resp.status_code == 403:
            logger.error(f"  Блокировка (HTTP {resp.status_code})")
            sys.exit(1)
        resp.raise_for_status()
        cache.save_collection(collection_id, resp.text)
        logger.success(f"Страница коллекции сохранена: {cache.get_collection_file(collection_id)}")
        return resp.text
    except requests.exceptions.RequestException as e:
        logger.error(f"Ошибка загрузки: {e}")
        return None

# ----------------------------------------------------------------------
# Работа с YAML конфигурацией
def load_config(config_path: Path, logger: Logger) -> Tuple[Optional[str], Dict[str, str]]:
    if not config_path.exists():
        return None, {}
    with open(config_path, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    collection_url = config.get('collection')
    syncmod_list = config.get('syncmod', [])
    syncmod_map = {}
    for item in syncmod_list:
        if isinstance(item, dict):
            for k, v in item.items():
                syncmod_map[str(k)] = str(v)
        elif isinstance(item, str) and ':' in item:
            k, v = item.split(':', 1)
            syncmod_map[k.strip()] = v.strip()
    return collection_url, syncmod_map

def generate_example_config(config_path: Path):
    example = """# Конфигурация парсинга коллекции Steam Workshop
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
"""
    config_path.write_text(example, encoding='utf-8')
    print(colorize(f"[SUCCESS] Создан пример конфигурации: {config_path}", 'GREEN'))

# ----------------------------------------------------------------------
# Очистка папки mods_pz/workshop/content/108600
def clean_mods_pz(valid_ids: Set[str], logger: Logger):
    mods_dir = Path("mods_pz/workshop/content/108600")
    if not mods_dir.exists():
        logger.info(f"Папка {mods_dir} не найдена, пропускаем очистку")
        return
    removed = 0
    kept = 0
    for item in mods_dir.iterdir():
        if item.is_dir():
            if item.name in valid_ids:
                kept += 1
            else:
                logger.warn(f"  🗑️  Удаляем лишний мод из mods_pz: {item.name} (не найден в коллекции)")
                shutil.rmtree(item)
                removed += 1
    if removed:
        print()
        print(colorize("═══════════════════════════════════════════════════════════════", 'YELLOW'))
        print(colorize("  📁  ОЧИСТКА mods_pz/workshop/content/108600               ", 'YELLOW'))
        print(colorize("═══════════════════════════════════════════════════════════════", 'YELLOW'))
        print(colorize(f"  Удалено лишних папок: {removed}", 'YELLOW'))
        print(colorize(f"  Оставлено папок: {kept}", 'YELLOW'))
        print(colorize("═══════════════════════════════════════════════════════════════", 'YELLOW'))
        print()
    else:
        logger.info(f"Лишних модов в mods_pz не найдено (папок: {kept})")

# ----------------------------------------------------------------------
# Генерация docker-compose.yml
def generate_docker_compose(workshop_ids: str, mod_ids: str, logger: Logger):
    compose_file = Path("../docker-compose.yml")
    if not workshop_ids or not mod_ids:
        logger.warn("Нет данных для генерации docker-compose.yml")
        return
    compose_file.parent.mkdir(parents=True, exist_ok=True)
    content = f"""services:
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
      - WORKSHOP_IDS={workshop_ids}
      - MOD_IDS={mod_ids}
    volumes:
      - ./server-data:/home/steam/Zomboid
      - ./mods_pz:/home/steam/pz-dedicated/steamapps
"""
    compose_file.write_text(content, encoding='utf-8')
    logger.success(f"docker-compose.yml создан: {compose_file}")

# ----------------------------------------------------------------------
# Основная функция
def main():
    parser = argparse.ArgumentParser(description="Парсер коллекций Steam Workshop (Python)")
    parser.add_argument("-c", "--config", help="Конфигурационный файл (YAML)", default="config.yaml")
    parser.add_argument("-u", "--url", help="URL коллекции напрямую")
    parser.add_argument("-t", "--cache-only", action="store_true", help="Использовать ТОЛЬКО кэш (не скачивать новые страницы)")
    parser.add_argument("-d", "--debug", action="store_true", help="Режим отладки")
    parser.add_argument("-g", "--generate", action="store_true", help="Сгенерировать пример конфигурации")
    parser.add_argument("-C", "--clean", action="store_true", help="Очистить кэш (папку modhtml/)")
    args = parser.parse_args()

    logger = Logger(debug=args.debug)
    MOD_HTML_DIR.mkdir(parents=True, exist_ok=True)

    # Генерация конфига
    if args.generate:
        generate_example_config(Path(args.config))
        return

    # Очистка кэша
    if args.clean:
        if MOD_HTML_DIR.exists():
            shutil.rmtree(MOD_HTML_DIR)
            logger.success("Кэш очищен (modhtml/)")
        else:
            logger.info("Папка modhtml/ не найдена")
        if not args.config and not args.url:
            return

    # Определяем URL коллекции
    collection_url = args.url
    syncmod_map = {}
    if args.config and Path(args.config).exists():
        url_from_config, syncmod_map = load_config(Path(args.config), logger)
        if not collection_url:
            collection_url = url_from_config
        if syncmod_map:
            logger.info(f"Загружено {len(syncmod_map)} правил синхронизации")
    if not collection_url:
        logger.error("Не указан URL коллекции. Используйте -u или укажите в config.yaml")
        sys.exit(1)

    logger.info(f"URL коллекции: {collection_url}")

    # Кэш с поддержкой только-кэш
    cache = PageCache(MOD_HTML_DIR, logger)
    cache.only_cache = args.cache_only

    # Загружаем страницу коллекции
    collection_id = extract_workshop_id_from_url(collection_url)
    if not collection_id:
        logger.error("Не удалось извлечь ID коллекции из URL")
        sys.exit(1)

    logger.info(f"ID коллекции: {collection_id}")

    collection_html = fetch_collection_page(collection_url, cache, logger)
    if not collection_html:
        logger.error("Не удалось загрузить страницу коллекции")
        sys.exit(1)

    workshop_ids = parse_workshop_ids_from_collection(collection_html)
    if not workshop_ids:
        logger.error("Не найдено предметов в коллекции")
        sys.exit(1)

    total_items = len(workshop_ids)
    logger.info(f"Найдено предметов в коллекции: {total_items}")

    # Очистка кэша от лишних
    valid_ids_set = set(workshop_ids)
    removed_cache, kept_cache = cache.delete_extra(valid_ids_set)
    if removed_cache:
        print()
        print(colorize("═══════════════════════════════════════════════════════════════", 'YELLOW'))
        print(colorize("  📁  ОЧИСТКА КЭША                                         ", 'YELLOW'))
        print(colorize("═══════════════════════════════════════════════════════════════", 'YELLOW'))
        print(colorize(f"  Удалено лишних папок: {removed_cache}", 'YELLOW'))
        print(colorize(f"  Оставлено папок: {kept_cache}", 'YELLOW'))
        print(colorize("═══════════════════════════════════════════════════════════════", 'YELLOW'))
        print()
    else:
        logger.info(f"Лишних модов в кэше не найдено (папок: {kept_cache})")

    # Очистка mods_pz
    clean_mods_pz(valid_ids_set, logger)

    # Подготовка результатов
    result_workshop_ids = []
    result_mod_ids = []
    warn_count = 0
    error_count = 0
    processed = 0
    cached_used = 0
    downloaded = 0

    for wid in workshop_ids:
        processed += 1
        print()
        logger.info(f"[{processed}/{total_items}] Обработка Workshop ID: {wid}")

        # Проверка syncmod
        if wid in syncmod_map:
            selected_mod_id = syncmod_map[wid]
            logger.info(f"  [SYNC] Используем syncmod: {selected_mod_id}")
            mod_ids = [selected_mod_id]
        else:
            # Получаем страницу мода
            mod_url = f"https://steamcommunity.com/sharedfiles/filedetails/?id={wid}"
            mod_html = fetch_page(mod_url, cache, logger, force_refresh=False)
            if not mod_html:
                logger.warn(f"  [SKIP] Пропускаем мод {wid} (не удалось получить страницу)")
                error_count += 1
                continue
            
            # Проверяем, был ли это кэш (файл существует)
            cache_file = cache._get_cache_file(wid)
            if cache_file.exists():
                cached_used += 1
            else:
                downloaded += 1

            mod_ids = parse_mod_ids_from_mod_page(mod_html, debug=args.debug)
            if args.debug and mod_ids:
                for idx, mid in enumerate(mod_ids, 1):
                    logger.debug(f"  [DEBUG] Извлечён Mod ID #{idx}: {mid}")

            if not mod_ids:
                logger.warn(f"  [WARN] Mod ID не найден для Workshop ID: {wid}")
                selected_mod_id = "unknown"
            elif len(mod_ids) == 1:
                selected_mod_id = mod_ids[0]
                logger.info(f"  [OK] Найден Mod ID: {selected_mod_id}")
            else:
                warn_count += 1
                logger.warn(f"  [WARN] Обнаружено несколько Mod ID для Workshop ID: {wid}")
                for mid in mod_ids:
                    logger.warn(f"    - {mid}")
                logger.warn(f"  [WARN] Используется первый: {mod_ids[0]}")
                logger.warn(f"  [WARN] Рекомендуется добавить в syncmod:")
                logger.warn(f"    - {wid} : \"{mod_ids[0]}\"")
                selected_mod_id = mod_ids[0]

        result_workshop_ids.append(wid)
        if selected_mod_id and selected_mod_id != "unknown":
            result_mod_ids.append(selected_mod_id)

    # Формируем строки
    if result_workshop_ids:
        workshop_ids_str = ";".join(result_workshop_ids) + ";"
    else:
        workshop_ids_str = ""
    if result_mod_ids:
        mod_ids_str = "\\\\" + ";\\\\".join(result_mod_ids) + ";"
    else:
        mod_ids_str = ""

    # Вывод результатов
    print()
    print(colorize("================================", 'GREEN'))
    print(colorize("Результаты парсинга", 'GREEN'))
    print(colorize("================================", 'GREEN'))
    if warn_count:
        print(colorize(f"ВНИМАНИЕ: Обнаружено {warn_count} предметов с несколькими Mod ID", 'YELLOW'))
        print(colorize("Рекомендуется добавить их в секцию syncmod в конфигурационном файле", 'YELLOW'))
        print()
    if error_count:
        print(colorize(f"ОШИБОК: {error_count} предметов не удалось обработать", 'YELLOW'))
        print()
    if args.cache_only:
        print(colorize("[РЕЖИМ КЭША] Использованы только локальные файлы", 'CYAN'))
        print()
    print(f"    - WORKSHOP_IDS={workshop_ids_str}")
    print(f"    - MOD_IDS={mod_ids_str}")

    # Статистика
    print()
    print(colorize("Статистика:", 'BLUE'))
    print(f"- Всего предметов в коллекции: {total_items}")
    print(f"- Успешно обработано: {processed}")
    print(f"- Использовано кэша: {cached_used}")
    if not args.cache_only:
        print(f"- Скачано новых: {downloaded}")
    else:
        print("- Режим: ТОЛЬКО КЭШ (скачивание отключено)")
    print(f"- Использовано syncmod: {len(syncmod_map)}")
    print(f"- Предупреждений (несколько Mod ID): {warn_count}")
    print(f"- Ошибок загрузки: {error_count}")
    print(f"- Папка с HTML модов: {MOD_HTML_DIR}/")

    # Сохраняем результат в файл
    result_file = Path("result.txt")
    with open(result_file, 'w', encoding='utf-8') as f:
        f.write(f"    - WORKSHOP_IDS={workshop_ids_str}\n")
        f.write(f"    - MOD_IDS={mod_ids_str}\n")
    logger.success(f"Результаты сохранены в: {result_file}")

    # Генерация docker-compose
    generate_docker_compose(workshop_ids_str, mod_ids_str, logger)

# ----------------------------------------------------------------------
if __name__ == "__main__":
    main()