"""Удаляет дубли из counting-training (одинаковые фото для одного productId).
Оставляет копию с employeeAnswer, удаляет остальные.
"""
import json, hashlib, os

base_dir = '/root/arabica_app/loyalty-proxy/data/counting-training'
samples_file = os.path.join(base_dir, 'samples.json')
images_dir = os.path.join(base_dir, 'images')
labels_dir = os.path.join(base_dir, 'labels')

with open(samples_file) as f:
    data = json.load(f)

samples = data.get('samples', [])
print(f'Total samples before: {len(samples)}')

# Group by (barcode, md5)
groups = {}
for s in samples:
    img_path = os.path.join(images_dir, s['imageFileName'])
    if os.path.exists(img_path):
        md5 = hashlib.md5(open(img_path, 'rb').read()).hexdigest()
    else:
        md5 = 'missing_' + s['id']
    key = (s.get('barcode', s.get('productId', '')), md5)
    groups.setdefault(key, []).append(s)

to_keep = []
to_delete = []
for key, group in groups.items():
    if len(group) == 1:
        to_keep.append(group[0])
        continue
    # Prefer one WITH employeeAnswer, then newest
    group.sort(key=lambda s: (
        1 if s.get('employeeAnswer') else 0,
        s.get('approvedAt', s.get('createdAt', ''))
    ), reverse=True)
    to_keep.append(group[0])
    to_delete.extend(group[1:])

print(f'Keeping: {len(to_keep)}, Deleting: {len(to_delete)}')

for s in to_delete:
    img_path = os.path.join(images_dir, s['imageFileName'])
    label_name = s['imageFileName'].replace('.jpg', '.txt')
    label_path = os.path.join(labels_dir, label_name)
    if os.path.exists(img_path):
        os.remove(img_path)
        print(f'  DEL img: {s["imageFileName"]}')
    if os.path.exists(label_path):
        os.remove(label_path)
        print(f'  DEL lbl: {label_name}')

data['samples'] = to_keep
with open(samples_file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f'\nTotal samples after: {len(to_keep)}')
