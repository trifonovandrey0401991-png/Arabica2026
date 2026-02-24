"""Fix product name typos in master catalog."""
import json

FILE = '/var/www/master-catalog/products.json'

with open(FILE) as f:
    products = json.load(f)

total_fixed = 0
for product in products:
    name = product.get('name', '')
    original = name

    # 1. WAWE → WAVE
    if 'WAWE' in name:
        name = name.replace('WAWE', 'WAVE')

    # 2. COFFE → COFFEE (only where COFFEE is missing the E)
    # Check: contains COFFE but NOT followed by E
    import re
    name = re.sub(r'COFFE(?!E)', 'COFFEE', name)

    # 3. MIX MOMENT → MIX MOMENTS (only without trailing S)
    if 'MIX MOMENT' in name and 'MIX MOMENTS' not in name:
        name = name.replace('MIX MOMENT', 'MIX MOMENTS')

    # 4. ЧЕРНИКА-МАЛИНА → ЧЕРНИКА МАЛИНА
    if 'ЧЕРНИКА-МАЛИНА' in name:
        name = name.replace('ЧЕРНИКА-МАЛИНА', 'ЧЕРНИКА МАЛИНА')

    # 5. GOLD VINTAGE → GOLD (VINTAGE) (only if no parens)
    if 'GOLD VINTAGE' in name and 'GOLD (VINTAGE)' not in name:
        name = name.replace('GOLD VINTAGE', 'GOLD (VINTAGE)')

    # 6. ЗЕЛЁНОЕ → ЗЕЛЕНОЕ
    if 'ЗЕЛЁНОЕ' in name:
        name = name.replace('ЗЕЛЁНОЕ', 'ЗЕЛЕНОЕ')

    if name != original:
        total_fixed += 1
        print(f'  [{original}]')
        print(f'  [{name}]')
        print()
        product['name'] = name

print(f'Total fixed: {total_fixed}')

if total_fixed > 0:
    with open(FILE, 'w') as f:
        json.dump(products, f, ensure_ascii=False, indent=2)
    print('Saved!')
else:
    print('Nothing to fix.')
