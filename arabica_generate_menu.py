import requests
import pandas as pd
import json
import os
from io import StringIO

# Ссылка на лист "Меню"
SHEET_URL = "https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/export?format=csv&gid=1604049969"

SAVE_PATH = r"C:\Users\Admin\arabica_app\assets\menu.json"

print("📄 Загружаю CSV из Google Sheets...")

response = requests.get(SHEET_URL)
response.raise_for_status()

raw = response.content

# Определение кодировки
try:
    text = raw.decode("utf-8-sig")
except:
    text = raw.decode("utf-16")

df = pd.read_csv(StringIO(text), dtype=str, header=0, keep_default_na=False)

print("🔹 Загружено строк:", len(df))
print("🔹 Столбцы:", df.columns.tolist())

menu_items = []

for i, row in df.iterrows():

    try:
        name = row.iloc[0].strip()     # A — Название
        price = row.iloc[1].strip()    # B — Цена
        category = row.iloc[2].strip() # C — Категория
        shop = row.iloc[3].strip()     # D — Магазин
        photo_id = row.iloc[5].strip() # F — Фото ID  ← ВАЖНО!!!!

        if not name:
            continue

        # Добавляем
        menu_items.append({
            "name": name,
            "price": price,
            "category": category,
            "shop": shop,
            "photo_id": photo_id
        })

    except Exception as e:
        print(f"❌ Ошибка в строке {i+1}: {e}")

# Сохраняем JSON
os.makedirs(os.path.dirname(SAVE_PATH), exist_ok=True)

with open(SAVE_PATH, "w", encoding="utf-8") as f:
    json.dump(menu_items, f, ensure_ascii=False, indent=2)

print("✅ menu.json успешно создан!")
print("🔢 Сохранено напитков:", len(menu_items))
print("📁 Файл:", SAVE_PATH)
