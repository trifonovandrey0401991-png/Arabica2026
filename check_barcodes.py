import json
import urllib.request

# Получаем мастер-каталог
print('=== MASTER CATALOG ===')
url = 'https://arabica26.ru/api/master-catalog'
req = urllib.request.Request(url)
req.add_header('Content-Type', 'application/json')

with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read().decode('utf-8'))

products = data.get('products', [])
print(f'Total products: {len(products)}')
print('First 10 barcodes:')
for p in products[:10]:
    barcode = p.get('barcode', 'NO_BARCODE')
    name = p.get('name', '')[:40]
    print(f'  barcode="{barcode}", name="{name}"')

# Сохраняем все баркоды из мастер-каталога
master_barcodes = set()
for p in products:
    bc = p.get('barcode')
    if bc:
        master_barcodes.add(str(bc))

print(f'\nUnique barcodes in master catalog: {len(master_barcodes)}')

# Получаем список магазинов с DBF
print('\n=== SHOP PRODUCTS (DBF) ===')
url = 'https://arabica26.ru/api/shop-products/shops'
req = urllib.request.Request(url)
req.add_header('Content-Type', 'application/json')

with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read().decode('utf-8'))

shops = data.get('shops', [])
print(f'Shops with DBF data: {len(shops)}')
for s in shops[:3]:
    print(f'  {s}')

if shops:
    # Берем первый магазин и смотрим его товары
    shop_id = shops[0].get('shopId')
    print(f'\nChecking products for shop: {shop_id}')

    url = f'https://arabica26.ru/api/shop-products/{shop_id}'
    req = urllib.request.Request(url)
    req.add_header('Content-Type', 'application/json')

    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode('utf-8'))

    dbf_products = data.get('products', [])
    print(f'Total DBF products: {len(dbf_products)}')
    print('First 10 kod values:')
    for p in dbf_products[:10]:
        kod = p.get('kod', 'NO_KOD')
        name = p.get('name', '')[:40]
        print(f'  kod="{kod}", name="{name}"')

    # Проверяем совпадения
    dbf_kods = set()
    for p in dbf_products:
        kod = p.get('kod')
        if kod:
            dbf_kods.add(str(kod))

    print(f'\nUnique kods in DBF: {len(dbf_kods)}')

    # Находим совпадения
    matches = master_barcodes & dbf_kods
    print(f'\n=== MATCHING ===')
    print(f'Matches found: {len(matches)}')
    if matches:
        print('Sample matches:')
        for m in list(matches)[:5]:
            print(f'  "{m}"')

    # Примеры несовпадений
    dbf_only = dbf_kods - master_barcodes
    master_only = master_barcodes - dbf_kods

    print(f'\nIn DBF but NOT in master catalog: {len(dbf_only)}')
    if dbf_only:
        print('Sample DBF-only:')
        for k in list(dbf_only)[:5]:
            print(f'  "{k}"')

    print(f'\nIn master catalog but NOT in DBF: {len(master_only)}')
    if master_only:
        print('Sample master-only:')
        for k in list(master_only)[:5]:
            print(f'  "{k}"')
