"""Проверка: все ли counting фото привязаны к карточкам в каталоге, совпадают ли имена."""
import json

with open('/tmp/products.json') as f:
    products = json.load(f).get('products', [])

samples_path = '/root/arabica_app/loyalty-proxy/data/counting-training/samples.json'
with open(samples_path) as f:
    samples = json.load(f).get('samples', [])

# Build catalog lookup
catalog_barcodes = set()
bc_to_name = {}
for p in products:
    for b in p.get('barcodes', [p.get('barcode', '')]):
        catalog_barcodes.add(b)
        bc_to_name[b] = p.get('productName', '')

print(f'Catalog cards: {len(products)}, Counting samples: {len(samples)}')
print(f'Unique catalog barcodes: {len(catalog_barcodes)}')
print()

# 1. Product cards without barcode or name
print('=== Cards without barcode or name ===')
bad_cards = 0
for p in products:
    issues = []
    if not p.get('barcode') and not p.get('barcodes'):
        issues.append('NO BARCODE')
    if not p.get('productName', '').strip():
        issues.append('NO NAME')
    if issues:
        bad_cards += 1
        print(f'  {p.get("productName","?")} | bc={p.get("barcode","?")} | {issues}')
if bad_cards == 0:
    print('  None - all OK')

# 2. Counting photos not matching any catalog card
print()
print('=== Counting photos NOT in catalog (orphans) ===')
orphans = 0
for s in samples:
    bc = s.get('barcode', s.get('productId', ''))
    if bc not in catalog_barcodes:
        orphans += 1
        print(f'  ORPHAN: {s.get("productName")} (bc={bc})')
if orphans == 0:
    print('  None - all match')

# 3. Name mismatches
print()
print('=== Name mismatches (photo vs catalog) ===')
mismatches = 0
for s in samples:
    bc = s.get('barcode', s.get('productId', ''))
    sname = s.get('productName', '')
    cname = bc_to_name.get(bc, '')
    if cname and sname and sname != cname:
        mismatches += 1
        print(f'  bc={bc}:')
        print(f'    Photo: [{sname}]')
        print(f'    Catalog: [{cname}]')
if mismatches == 0:
    print('  None - all match')

# 4. Cards with counting photos assigned to wrong name via grouping
print()
print('=== Grouping check: same barcode, different names ===')
from collections import defaultdict
bc_names = defaultdict(set)
for s in samples:
    bc = s.get('barcode', s.get('productId', ''))
    bc_names[bc].add(s.get('productName', ''))
conflicts = 0
for bc, names in bc_names.items():
    if len(names) > 1:
        conflicts += 1
        print(f'  bc={bc}: {list(names)}')
if conflicts == 0:
    print('  None - consistent')
