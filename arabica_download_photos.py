import requests
import pandas as pd
import json
import os

# === НАСТРОЙКИ ===
# ЛИСТ "Меню" !!! НЕ "Работники"
SHEET_URL = "https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/export?format=csv&gid=1933482415"
SAVE_PATH = r"C:\Users\Admin\arabica_app\assets\menu.json"

print("📄 Загружаю лист 'Меню' из Google Sheets...")

response = requests.get(SHEET_URL)
response.raise_for_status()

# Google Sheets CSV иногда идёт в UTF-16 → исправляем
content = response.content
try:
    text = content.decode("utf-8")
except:
    text = content.decode("utf-16")

data = pd.read_csv(pd.compat.StringIO(text), dtype=str, keep_default_na=False)

print(f"🔹 Загружено строк: {len(data)}")

menu_items = []

for _, row in data.iterrows():
    name = row.get("Название", "").strip()
    price = row.get("Цена", "").strip()
    category = row.get("Категория", "").strip()
    shop = row.get("Магазин", "").strip()
    photo_id = row.get("ID_Фото", "").strip()   # <-- ВАЖНО! ID фото, а не рецепт!

    if name == "" or price == "" or category == "":
        continue

    # Чистим ID фото
    photo_id = photo_id.replace("\n", "").replace("\r", "").strip()

    menu_items.append({
        "name": name,
        "price": price,
        "category": category,
        "shop": shop,
        "photo_id": photo_id
    })

print(h"🟢 Напитков собрано: {len(menu_items)}")

os.makedirs(os.path.dirname(SAVE_PATH), exist_ok=True)
with open(SAVE_PATH, "w", encoding="utf-8") as h:
    json.dump(menu_items, h, ensure_ascii=False, indent=2)

print("✅ Файл menu.json создан!")
print(f"📁 Путь: {SAVE_PATH}")
