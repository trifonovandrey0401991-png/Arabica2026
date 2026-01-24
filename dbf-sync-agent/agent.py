#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DBF Sync Agent
Агент синхронизации товаров из DBF файла на сервер

Устанавливается на ПК магазина и мониторит изменения в tov.dbf,
отправляя обновления на сервер в реальном времени.

Использование:
    python agent.py

Требования:
    pip install watchdog requests

Конфигурация:
    Создайте config.json рядом с agent.py (см. config.example.json)
"""

import os
import sys
import json
import time
import struct
import logging
import requests
from datetime import datetime
from pathlib import Path

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('sync.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

# Путь к конфигурации
CONFIG_FILE = Path(__file__).parent / 'config.json'

# Дефолтные настройки
DEFAULT_CONFIG = {
    'shopId': 'shop_1',
    'shopName': 'Магазин 1',
    'dbfPath': 'C:\\Database\\tov.dbf',
    'serverUrl': 'https://arabica26.ru',
    'apiKey': 'arabica-sync-2025',
    'syncIntervalSeconds': 60,
    'encoding': 'cp866',
    'fields': {
        'kod': 'KOD',
        'name': 'NAME',
        'group': 'ГРУППА',
        'stock': 'ОСТ'
    }
}


def load_config():
    """Загрузить конфигурацию из файла"""
    if not CONFIG_FILE.exists():
        logger.warning(f'Конфигурация не найдена: {CONFIG_FILE}')
        logger.info('Используем настройки по умолчанию')
        return DEFAULT_CONFIG

    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            config = json.load(f)
            # Мерджим с дефолтными значениями
            for key, value in DEFAULT_CONFIG.items():
                if key not in config:
                    config[key] = value
            return config
    except Exception as e:
        logger.error(f'Ошибка загрузки конфигурации: {e}')
        return DEFAULT_CONFIG


def parse_dbf(dbf_path, encoding='cp866'):
    """
    Парсинг DBF файла

    Args:
        dbf_path: Путь к DBF файлу
        encoding: Кодировка файла (обычно cp866 для русского)

    Returns:
        list: Список словарей с данными записей
    """
    records = []

    try:
        with open(dbf_path, 'rb') as f:
            # Читаем заголовок DBF
            header = f.read(32)

            if len(header) < 32:
                logger.error('Файл DBF слишком короткий')
                return records

            # Парсим заголовок
            num_records = struct.unpack('<I', header[4:8])[0]
            header_size = struct.unpack('<H', header[8:10])[0]
            record_size = struct.unpack('<H', header[10:12])[0]

            logger.info(f'DBF: {num_records} записей, заголовок {header_size} байт, запись {record_size} байт')

            # Читаем описания полей
            fields = []
            f.seek(32)

            while True:
                field_header = f.read(32)
                if len(field_header) < 32 or field_header[0] == 0x0D:
                    break

                field_name = field_header[0:11].split(b'\x00')[0].decode('ascii', errors='ignore').strip()
                field_type = chr(field_header[11])
                field_size = field_header[16]

                fields.append({
                    'name': field_name,
                    'type': field_type,
                    'size': field_size
                })

            logger.info(f'DBF полей: {len(fields)}')

            # Читаем записи
            f.seek(header_size)

            for i in range(num_records):
                record_data = f.read(record_size)

                if len(record_data) < record_size:
                    break

                # Первый байт - флаг удаления
                if record_data[0] == 0x2A:  # '*' = deleted
                    continue

                record = {}
                offset = 1  # Пропускаем байт удаления

                for field in fields:
                    value = record_data[offset:offset + field['size']]

                    try:
                        value = value.decode(encoding, errors='ignore').strip()
                    except:
                        value = value.decode('latin-1', errors='ignore').strip()

                    # Преобразуем числовые поля
                    if field['type'] == 'N':
                        try:
                            if '.' in value:
                                value = float(value) if value else 0.0
                            else:
                                value = int(value) if value else 0
                        except:
                            value = 0

                    record[field['name']] = value
                    offset += field['size']

                records.append(record)

            logger.info(f'DBF: прочитано {len(records)} активных записей')

    except FileNotFoundError:
        logger.error(f'Файл не найден: {dbf_path}')
    except Exception as e:
        logger.error(f'Ошибка парсинга DBF: {e}')

    return records


def extract_products(records, config):
    """
    Извлечь товары из записей DBF по настроенным полям

    Args:
        records: Список записей из DBF
        config: Конфигурация

    Returns:
        list: Список товаров в формате для API
    """
    products = []
    field_mapping = config.get('fields', DEFAULT_CONFIG['fields'])

    kod_field = field_mapping.get('kod', 'KOD')
    name_field = field_mapping.get('name', 'NAME')
    group_field = field_mapping.get('group', 'ГРУППА')
    stock_field = field_mapping.get('stock', 'ОСТ')

    for record in records:
        kod = str(record.get(kod_field, '')).strip()
        name = str(record.get(name_field, '')).strip()
        group = str(record.get(group_field, '')).strip()
        stock = record.get(stock_field, 0)

        # Пропускаем записи без кода или названия
        if not kod or not name:
            continue

        # Преобразуем остаток в число
        if isinstance(stock, str):
            try:
                stock = float(stock.replace(',', '.'))
            except:
                stock = 0

        products.append({
            'kod': kod,
            'name': name,
            'group': group,
            'stock': int(stock)
        })

    return products


def sync_to_server(products, config):
    """
    Отправить товары на сервер

    Args:
        products: Список товаров
        config: Конфигурация

    Returns:
        bool: Успешность синхронизации
    """
    server_url = config['serverUrl'].rstrip('/')
    shop_id = config['shopId']
    api_key = config['apiKey']

    url = f'{server_url}/api/shop-products/{shop_id}/sync'

    try:
        response = requests.post(
            url,
            json={'products': products},
            headers={
                'Content-Type': 'application/json',
                'X-API-Key': api_key
            },
            timeout=30
        )

        if response.status_code == 200:
            result = response.json()
            logger.info(f'✅ Синхронизация успешна: {result.get("productCount", 0)} товаров')
            return True
        elif response.status_code == 401:
            logger.error('❌ Неверный API ключ')
            return False
        else:
            logger.error(f'❌ Ошибка сервера: {response.status_code} - {response.text}')
            return False

    except requests.exceptions.Timeout:
        logger.error('❌ Таймаут соединения с сервером')
        return False
    except requests.exceptions.ConnectionError:
        logger.error('❌ Не удалось подключиться к серверу')
        return False
    except Exception as e:
        logger.error(f'❌ Ошибка синхронизации: {e}')
        return False


def get_file_mtime(path):
    """Получить время модификации файла"""
    try:
        return os.path.getmtime(path)
    except:
        return 0


def run_sync_loop(config):
    """
    Основной цикл синхронизации

    Мониторит файл DBF и отправляет изменения на сервер
    """
    dbf_path = config['dbfPath']
    interval = config.get('syncIntervalSeconds', 60)
    encoding = config.get('encoding', 'cp866')

    logger.info('=' * 50)
    logger.info(f'DBF Sync Agent v1.0')
    logger.info(f'Магазин: {config["shopName"]} ({config["shopId"]})')
    logger.info(f'DBF файл: {dbf_path}')
    logger.info(f'Сервер: {config["serverUrl"]}')
    logger.info(f'Интервал: {interval} сек')
    logger.info('=' * 50)

    last_mtime = 0
    last_sync = 0

    while True:
        try:
            current_time = time.time()
            current_mtime = get_file_mtime(dbf_path)

            # Синхронизируем если:
            # 1. Файл изменился
            # 2. Или прошло достаточно времени с последней синхронизации
            should_sync = False

            if current_mtime > last_mtime:
                logger.info(f'📁 Обнаружено изменение файла DBF')
                should_sync = True
                last_mtime = current_mtime
            elif current_time - last_sync >= interval:
                logger.info(f'⏰ Периодическая синхронизация')
                should_sync = True

            if should_sync:
                # Парсим DBF
                records = parse_dbf(dbf_path, encoding)

                if records:
                    # Извлекаем товары
                    products = extract_products(records, config)
                    logger.info(f'📦 Найдено {len(products)} товаров')

                    # Отправляем на сервер
                    if products:
                        sync_to_server(products, config)
                        last_sync = current_time
                else:
                    logger.warning('⚠️ Записи не найдены в DBF')

            # Ждём перед следующей проверкой
            time.sleep(5)  # Проверяем каждые 5 секунд

        except KeyboardInterrupt:
            logger.info('🛑 Остановка агента...')
            break
        except Exception as e:
            logger.error(f'❌ Ошибка в цикле синхронизации: {e}')
            time.sleep(10)


def main():
    """Точка входа"""
    logger.info('🚀 Запуск DBF Sync Agent...')

    # Загружаем конфигурацию
    config = load_config()

    # Проверяем существование файла DBF
    if not os.path.exists(config['dbfPath']):
        logger.error(f'❌ Файл DBF не найден: {config["dbfPath"]}')
        logger.info('Проверьте путь в config.json')
        sys.exit(1)

    # Запускаем цикл синхронизации
    run_sync_loop(config)


if __name__ == '__main__':
    main()
