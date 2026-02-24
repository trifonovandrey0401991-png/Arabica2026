"""Поиск потенциальных дублей в каталоге через Levenshtein + совпадение бренда."""
import json, re

def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    prev = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        curr = [i + 1]
        for j, c2 in enumerate(s2):
            curr.append(min(prev[j+1]+1, curr[j]+1, prev[j]+(c1!=c2)))
        prev = curr
    return prev[len(s2)]

def extract_brand(name):
    """Извлечь бренд из кавычек: "HEETS" PURPLE WAVE → HEETS"""
    m = re.match(r'"([^"]+)"', name)
    return m.group(1).upper().strip() if m else name.split()[0].upper() if name else ''

with open('/tmp/products.json') as f:
    prods = json.load(f).get('products', [])

# Группировка уже произошла на сервере — нам нужны сырые (ungrouped)
# Но у нас grouped данные. Работаем с тем что есть.
names = {}
for p in prods:
    name = p.get('productName', '')
    if name not in names:
        names[name] = {
            'barcodes': p.get('barcodes', [p.get('barcode', '')]),
            'brand': extract_brand(name),
        }

name_list = sorted(names.keys())
print(f'Уникальных названий: {len(name_list)}')
print()

# Сравнить каждую пару с одинаковым брендом
found = []
for i in range(len(name_list)):
    for j in range(i+1, len(name_list)):
        n1, n2 = name_list[i], name_list[j]
        b1, b2 = names[n1]['brand'], names[n2]['brand']
        if b1 != b2:
            continue
        dist = levenshtein(n1, n2)
        # Порог: до 2 символов разницы, но не более 10% длины
        max_dist = min(2, max(1, len(n1) // 10))
        if dist <= max_dist:
            found.append((n1, n2, dist, b1))

print(f'Найдено потенциальных дублей: {len(found)}')
print()
for n1, n2, dist, brand in found:
    bc1 = names[n1]['barcodes']
    bc2 = names[n2]['barcodes']
    # Подсветить разницу
    diff_chars = []
    for k in range(min(len(n1), len(n2))):
        if n1[k] != n2[k]:
            diff_chars.append(k)
    print(f'  Бренд: {brand} | Расстояние: {dist}')
    print(f'    1: {n1}')
    print(f'       barcodes: {bc1}')
    print(f'    2: {n2}')
    print(f'       barcodes: {bc2}')
    if diff_chars:
        marker = ''.join('^' if k in diff_chars else ' ' for k in range(max(len(n1),len(n2))))
        print(f'       {"":>4}{marker}')
    print()

if not found:
    print('Дублей не найдено.')
