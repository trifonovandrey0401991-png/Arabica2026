"""Check orphan counting barcodes against FULL catalog."""
import json

with open('/tmp/products.json') as f:
    prods = json.load(f).get('products', [])

print(f'Catalog products: {len(prods)}')

# All barcodes in catalog
all_bc = set()
bc_to_name = {}
for p in prods:
    for b in p.get('barcodes', [p.get('barcode', '')]):
        all_bc.add(str(b))
        bc_to_name[str(b)] = p.get('productName', '')

print(f'Unique catalog barcodes: {len(all_bc)}')

# Load counting samples
with open('/root/arabica_app/loyalty-proxy/data/counting-training/samples.json') as f:
    samples = json.load(f).get('samples', [])

# Unique barcodes in counting
counting_bcs = set()
for s in samples:
    counting_bcs.add(s.get('barcode', s.get('productId', '')))

print(f'Unique counting barcodes: {len(counting_bcs)}')
print()

for obc in sorted(counting_bcs):
    if obc in all_bc:
        print(f'  OK      {obc} -> {bc_to_name[obc]}')
    else:
        # Partial match
        matches = [b for b in all_bc if obc in b or b in obc]
        if matches:
            print(f'  PARTIAL {obc} ~ {matches[0]} -> {bc_to_name[matches[0]]}')
        else:
            print(f'  MISS    {obc} (no match in catalog)')

# Show barcode format stats
short = [b for b in counting_bcs if len(b) <= 8]
long_ = [b for b in counting_bcs if len(b) > 8]
print(f'\nBarcode format: {len(short)} short (<=8), {len(long_)} long (>8)')
print(f'Short: {sorted(short)[:5]}...')
print(f'Long: {sorted(long_)[:5]}...')
