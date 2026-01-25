import json
import urllib.request

# Получаем все товары
print('Loading products...')
url = 'https://arabica26.ru/api/master-catalog'
req = urllib.request.Request(url)
req.add_header('Content-Type', 'application/json')

with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read().decode('utf-8'))

products = data.get('products', [])
print(f'Total products: {len(products)}')

# Обновляем каждый товар
updated = 0
already_active = 0
for p in products:
    if p.get('isAiActive', False):
        already_active += 1
        continue

    product_id = p['id']
    url = f'https://arabica26.ru/api/master-catalog/{product_id}/ai-status'
    req_data = json.dumps({'isAiActive': True}).encode('utf-8')
    req = urllib.request.Request(url, data=req_data, method='PATCH')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 200:
                updated += 1
                name = p.get('name', '')[:40]
                print(f'[OK] {updated}: {name}...')
    except Exception as e:
        print(f'[ERR] Error for {product_id}: {e}')

print(f'\n=== Result ===')
print(f'Already active: {already_active}')
print(f'Updated: {updated}')
print(f'Total with AI: {already_active + updated}')
