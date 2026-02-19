#!/usr/bin/env python3
"""Rename menu photo files from Telegram IDs to drink names."""
import subprocess, json, re, os, shutil

ASSETS_DIR = '/root/arabica_app/assets/images'

# Get mapping from DB
result = subprocess.run(
    ['sudo', '-u', 'postgres', 'psql', '-d', 'arabica_db', '-t', '-A', '-c',
     "SELECT DISTINCT ON (data->>'photo_id') data->>'photo_id', data->>'name' "
     "FROM menu_items WHERE data->>'photo_id' IS NOT NULL AND data->>'photo_id' != '' "
     "ORDER BY data->>'photo_id', data->>'name';"],
    capture_output=True, text=True
)

mapping = {}
seen_names = {}

for line in result.stdout.strip().split('\n'):
    if '|' not in line:
        continue
    photo_id, name = line.split('|', 1)
    photo_id = photo_id.strip()
    name = name.strip()

    # Sanitize: remove emojis, keep cyrillic/latin/digits/spaces/hyphens
    clean = re.sub(r'[^\w\s\-]', '', name, flags=re.UNICODE)
    clean = re.sub(r'\s+', '_', clean.strip()).lower()

    # Handle duplicates
    if clean in seen_names:
        seen_names[clean] += 1
        clean = f"{clean}_{seen_names[clean]}"
    else:
        seen_names[clean] = 1

    old_file = os.path.join(ASSETS_DIR, f'{photo_id}.jpg')
    new_file = os.path.join(ASSETS_DIR, f'{clean}.jpg')

    if os.path.exists(old_file):
        mapping[photo_id] = clean
        shutil.move(old_file, new_file)
        print(f'OK: {name} -> {clean}.jpg')
    else:
        print(f'MISS: {name} ({photo_id[:40]}...)')

print(f'\nRenamed: {len(mapping)} files')

# Save mapping for DB update
with open('/tmp/menu_photo_mapping.json', 'w') as f:
    json.dump(mapping, f, ensure_ascii=False, indent=2)

# Update DB
for old_id, new_id in mapping.items():
    sql = f"UPDATE menu_items SET data = jsonb_set(data, '{{photo_id}}', '\"{new_id}\"') WHERE data->>'photo_id' = '{old_id}';"
    r = subprocess.run(
        ['sudo', '-u', 'postgres', 'psql', '-d', 'arabica_db', '-c', sql],
        capture_output=True, text=True
    )
    count = r.stdout.strip().split('\n')[-1] if r.stdout else '?'
    print(f'  DB: {new_id} <- {count}')

print('\nDone! DB updated.')
