from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

# === CONSTANTS ===
W, H = 1080, 1920
EMERALD = (26, 77, 77)
DARK = (13, 46, 46)
NIGHT = (5, 21, 21)
GOLD = (212, 175, 55)
WHITE = (255, 255, 255)
LIGHT_TEAL = (180, 220, 220)
SCREEN_BG = (8, 30, 30)
CARD_BG = (20, 60, 60)
CARD_BORDER = (35, 90, 90)

OUT_DIR = "c:/Users/Admin/arabica2026/assets/images/screenshots"
os.makedirs(OUT_DIR, exist_ok=True)

font_title = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 52)
font_subtitle = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 34)
font_screen_title = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 28)
font_screen_text = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
font_screen_small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)
font_icon = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 40)
font_number = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 48)


def make_gradient(w, h, c1, c2):
    img = Image.new("RGB", (w, h))
    for i in range(h):
        t = i / h
        r = int(c1[0] + (c2[0] - c1[0]) * t)
        g = int(c1[1] + (c2[1] - c1[1]) * t)
        b = int(c1[2] + (c2[2] - c1[2]) * t)
        ImageDraw.Draw(img).line([(0, i), (w - 1, i)], fill=(r, g, b))
    return img


def draw_rounded_rect(draw, xy, fill, radius=20, outline=None, width=0):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def create_base(title_text, subtitle_text):
    img = make_gradient(W, H, NIGHT, DARK)
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), title_text, font=font_title)
    tw = bbox[2] - bbox[0]
    draw.text(((W - tw) // 2, 80), title_text, fill=GOLD, font=font_title)
    bbox2 = draw.textbbox((0, 0), subtitle_text, font=font_subtitle)
    sw = bbox2[2] - bbox2[0]
    draw.text(((W - sw) // 2, 150), subtitle_text, fill=LIGHT_TEAL, font=font_subtitle)
    draw.line([(W // 2 - 60, 210), (W // 2 + 60, 210)], fill=GOLD, width=2)
    return img, draw


def draw_phone(draw):
    px, py = 90, 250
    pw, ph = W - 180, H - 350
    radius = 40
    draw_rounded_rect(draw, [px - 4, py - 4, px + pw + 4, py + ph + 4], fill=(40, 40, 40), radius=radius + 4)
    draw_rounded_rect(draw, [px, py, px + pw, py + ph], fill=SCREEN_BG, radius=radius)
    draw.rectangle([px + radius, py, px + pw - radius, py + 35], fill=(12, 38, 38))
    draw.text((px + pw // 2 - 20, py + 8), "12:00", fill=WHITE, font=font_screen_small)
    return px + 15, py + 45, pw - 30, ph - 60


def draw_card(draw, x, y, w, h, title, items=None, icon_text=None):
    draw_rounded_rect(draw, [x, y, x + w, y + h], fill=CARD_BG, radius=16, outline=CARD_BORDER, width=1)
    if icon_text:
        draw.text((x + 15, y + 12), icon_text, fill=GOLD, font=font_icon)
        draw.text((x + 65, y + 18), title, fill=WHITE, font=font_screen_title)
    else:
        draw.text((x + 15, y + 12), title, fill=WHITE, font=font_screen_title)
    if items:
        for i, item in enumerate(items):
            iy = y + 55 + i * 28
            draw.text((x + 40, iy), item, fill=LIGHT_TEAL, font=font_screen_text)


def draw_tile(draw, x, y, w, h, icon, label, value=None):
    draw_rounded_rect(draw, [x, y, x + w, y + h], fill=CARD_BG, radius=14, outline=CARD_BORDER, width=1)
    draw.text((x + w // 2 - 15, y + 15), icon, fill=GOLD, font=font_icon)
    bbox = draw.textbbox((0, 0), label, font=font_screen_small)
    lw = bbox[2] - bbox[0]
    draw.text((x + (w - lw) // 2, y + h - 55), label, fill=LIGHT_TEAL, font=font_screen_small)
    if value:
        bbox2 = draw.textbbox((0, 0), value, font=font_screen_title)
        vw = bbox2[2] - bbox2[0]
        draw.text((x + (w - vw) // 2, y + 60), value, fill=WHITE, font=font_screen_title)


# ===== 1: Dashboard =====
img, draw = create_base("Управление", "Всё в одном приложении")
sx, sy, sw, sh = draw_phone(draw)
draw_rounded_rect(draw, [sx, sy, sx + sw, sy + 55], fill=(15, 48, 48), radius=0)
draw.text((sx + 15, sy + 12), "ARABICA", fill=GOLD, font=font_screen_title)

tile_w = (sw - 30) // 2
tile_h = 130
tile_y = sy + 75
for i, (icon, label, val) in enumerate([
    ("\u2615", "Смены", "5"), ("\U0001f4ca", "Отчёты", "12"),
    ("\U0001f465", "Сотрудники", "24"), ("\u2b50", "Рейтинг", "87%")
]):
    tx = sx + 10 + (i % 2) * (tile_w + 10)
    ty = tile_y + (i // 2) * (tile_h + 10)
    draw_tile(draw, tx, ty, tile_w, tile_h, icon, label, val)

card_y = tile_y + 2 * (tile_h + 10) + 20
draw_card(draw, sx + 10, card_y, sw - 20, 150, "Сегодня",
          items=["3 магазина открыты", "2 пересменки ожидают", "1 новый отзыв"], icon_text="\U0001f4cb")
draw_card(draw, sx + 10, card_y + 170, sw - 20, 150, "Уведомления",
          items=["Иванова сдала смену", "Новый заказ #127", "Пересчёт: Центральная"], icon_text="\U0001f514")

nav_y = sy + sh - 60
draw.rectangle([sx, nav_y, sx + sw, nav_y + 60], fill=(12, 38, 38))
for i, item in enumerate(["Главная", "Отчёты", "Магазины", "Ещё"]):
    nx = sx + i * (sw // 4) + sw // 8
    bbox = draw.textbbox((0, 0), item, font=font_screen_small)
    nw = bbox[2] - bbox[0]
    draw.text((nx - nw // 2, nav_y + 25), item, fill=GOLD if i == 0 else (120, 160, 160), font=font_screen_small)

img.save(f"{OUT_DIR}/01_dashboard.png", "PNG")
print("1/6 done")


# ===== 2: Reports =====
img, draw = create_base("Отчёты и смены", "Полный контроль каждый день")
sx, sy, sw, sh = draw_phone(draw)
draw_rounded_rect(draw, [sx, sy, sx + sw, sy + 55], fill=(15, 48, 48), radius=0)
draw.text((sx + 15, sy + 12), "Пересменки", fill=GOLD, font=font_screen_title)

tab_y = sy + 60
for i, tab in enumerate(["Сегодня", "Неделя", "Месяц"]):
    tx = sx + i * (sw // 3)
    tw = sw // 3
    bbox = draw.textbbox((0, 0), tab, font=font_screen_small)
    ttw = bbox[2] - bbox[0]
    draw.text((tx + (tw - ttw) // 2, tab_y + 8), tab, fill=GOLD if i == 0 else (80, 120, 120), font=font_screen_small)
    if i == 0:
        draw.line([(tx + 10, tab_y + 32), (tx + tw - 10, tab_y + 32)], fill=GOLD, width=2)

reports = [
    ("Центральная", "Иванова А.", "\u2705 Сдано", "09:00", (80, 180, 80)),
    ("Набережная", "Петрова М.", "\u23f3 Ожидает", "\u2014", GOLD),
    ("Парковая", "Сидорова К.", "\u2705 Сдано", "08:45", (80, 180, 80)),
    ("Университет", "Козлова Д.", "\u274c Просрочено", "\u2014", (200, 80, 80)),
]
card_y = tab_y + 45
for i, (shop, name, status, time, scolor) in enumerate(reports):
    cy = card_y + i * 125
    draw_rounded_rect(draw, [sx + 10, cy, sx + sw - 10, cy + 110], fill=CARD_BG, radius=14, outline=CARD_BORDER, width=1)
    draw.text((sx + 25, cy + 10), shop, fill=WHITE, font=font_screen_title)
    draw.text((sx + 25, cy + 42), name, fill=LIGHT_TEAL, font=font_screen_text)
    draw.text((sx + 25, cy + 72), status, fill=scolor, font=font_screen_text)
    if time != "\u2014":
        draw.text((sx + sw - 90, cy + 15), time, fill=(150, 190, 190), font=font_screen_text)

sum_y = card_y + 4 * 125 + 15
draw_rounded_rect(draw, [sx + 10, sum_y, sx + sw - 10, sum_y + 80], fill=(20, 50, 50), radius=14, outline=GOLD, width=1)
draw.text((sx + 25, sum_y + 10), "Итого: 2 из 4 сдано", fill=GOLD, font=font_screen_title)
draw.text((sx + 25, sum_y + 45), "Следующий дедлайн: 14:00", fill=LIGHT_TEAL, font=font_screen_text)
img.save(f"{OUT_DIR}/02_reports.png", "PNG")
print("2/6 done")


# ===== 3: Efficiency =====
img, draw = create_base("Эффективность", "Рейтинг каждого сотрудника")
sx, sy, sw, sh = draw_phone(draw)
draw_rounded_rect(draw, [sx, sy, sx + sw, sy + 55], fill=(15, 48, 48), radius=0)
draw.text((sx + 15, sy + 12), "Эффективность", fill=GOLD, font=font_screen_title)

employees = [
    ("Иванова Анна", "92%", [(0.9, "Смены"), (0.95, "Отчёты"), (0.88, "Обучение")]),
    ("Петрова Мария", "85%", [(0.82, "Смены"), (0.9, "Отчёты"), (0.80, "Обучение")]),
    ("Сидорова Катя", "78%", [(0.75, "Смены"), (0.85, "Отчёты"), (0.70, "Обучение")]),
]
ey = sy + 70
for i, (name, score, bars) in enumerate(employees):
    cy = ey + i * 240
    draw_rounded_rect(draw, [sx + 10, cy, sx + sw - 10, cy + 225], fill=CARD_BG, radius=14, outline=CARD_BORDER, width=1)
    draw.text((sx + 25, cy + 12), name, fill=WHITE, font=font_screen_title)
    score_val = int(score[:-1])
    score_color = (80, 200, 80) if score_val >= 85 else GOLD if score_val >= 75 else (200, 120, 80)
    bbox = draw.textbbox((0, 0), score, font=font_number)
    score_w = bbox[2] - bbox[0]
    draw.text((sx + sw - score_w - 30, cy + 5), score, fill=score_color, font=font_number)
    for j, (val, label) in enumerate(bars):
        by = cy + 60 + j * 50
        bar_x = sx + 25
        bar_w = sw - 60
        draw.text((bar_x, by), label, fill=LIGHT_TEAL, font=font_screen_small)
        draw_rounded_rect(draw, [bar_x, by + 24, bar_x + bar_w, by + 38], fill=(15, 40, 40), radius=7)
        fill_w = int(bar_w * val)
        if fill_w > 14:
            bar_color = (80, 180, 80) if val >= 0.85 else GOLD if val >= 0.75 else (200, 120, 80)
            draw_rounded_rect(draw, [bar_x, by + 24, bar_x + fill_w, by + 38], fill=bar_color, radius=7)

img.save(f"{OUT_DIR}/03_efficiency.png", "PNG")
print("3/6 done")


# ===== 4: Loyalty =====
img, draw = create_base("Программа лояльности", "Бонусы за каждую покупку")
sx, sy, sw, sh = draw_phone(draw)
draw_rounded_rect(draw, [sx, sy, sx + sw, sy + 55], fill=(15, 48, 48), radius=0)
draw.text((sx + 15, sy + 12), "Мои бонусы", fill=GOLD, font=font_screen_title)

ly = sy + 75
draw_rounded_rect(draw, [sx + 15, ly, sx + sw - 15, ly + 180], fill=EMERALD, radius=20, outline=GOLD, width=2)
draw.text((sx + 35, ly + 15), "ARABICA GOLD", fill=GOLD, font=font_screen_title)
draw.text((sx + 35, ly + 55), "Ваши баллы:", fill=LIGHT_TEAL, font=font_screen_text)
big_font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 64)
draw.text((sx + 35, ly + 85), "1,250", fill=GOLD, font=big_font)
draw.text((sx + 250, ly + 110), "баллов", fill=LIGHT_TEAL, font=font_screen_text)

btn_y = ly + 200
btns = ["Меню", "Заказать", "Колесо удачи", "Отзывы"]
btn_w = (sw - 50) // 2
for i, btn in enumerate(btns):
    bx = sx + 15 + (i % 2) * (btn_w + 10)
    by = btn_y + (i // 2) * 70
    draw_rounded_rect(draw, [bx, by, bx + btn_w, by + 58], fill=CARD_BG, radius=12, outline=CARD_BORDER, width=1)
    bbox = draw.textbbox((0, 0), btn, font=font_screen_text)
    btw = bbox[2] - bbox[0]
    draw.text((bx + (btn_w - btw) // 2, by + 18), btn, fill=GOLD, font=font_screen_text)

ry = btn_y + 160
draw.text((sx + 20, ry), "Последние покупки", fill=WHITE, font=font_screen_title)
for i, (item, pts, date) in enumerate([
    ("Капучино 0.3", "+15 баллов", "Сегодня"),
    ("Латте 0.4 + Круассан", "+25 баллов", "Вчера"),
    ("Раф 0.3", "+15 баллов", "28 фев"),
]):
    py2 = ry + 40 + i * 65
    draw_rounded_rect(draw, [sx + 10, py2, sx + sw - 10, py2 + 55], fill=CARD_BG, radius=10)
    draw.text((sx + 25, py2 + 5), item, fill=WHITE, font=font_screen_text)
    draw.text((sx + 25, py2 + 30), date, fill=(120, 160, 160), font=font_screen_small)
    draw.text((sx + sw - 150, py2 + 15), pts, fill=(80, 200, 80), font=font_screen_text)

img.save(f"{OUT_DIR}/04_loyalty.png", "PNG")
print("4/6 done")


# ===== 5: Menu =====
img, draw = create_base("Меню и заказы", "Закажи напиток заранее")
sx, sy, sw, sh = draw_phone(draw)
draw_rounded_rect(draw, [sx, sy, sx + sw, sy + 55], fill=(15, 48, 48), radius=0)
draw.text((sx + 15, sy + 12), "Меню", fill=GOLD, font=font_screen_title)

cat_y = sy + 65
cats = ["Кофе", "Чай", "Десерты", "Еда"]
cat_w = (sw - 50) // 4
for i, cat in enumerate(cats):
    cx = sx + 10 + i * (cat_w + 10)
    sel = i == 0
    draw_rounded_rect(draw, [cx, cat_y, cx + cat_w, cat_y + 38], fill=EMERALD if sel else CARD_BG, radius=19, outline=GOLD if sel else CARD_BORDER, width=1)
    bbox = draw.textbbox((0, 0), cat, font=font_screen_small)
    cw = bbox[2] - bbox[0]
    draw.text((cx + (cat_w - cw) // 2, cat_y + 10), cat, fill=GOLD if sel else LIGHT_TEAL, font=font_screen_small)

items_data = [
    ("Капучино", "0.3 / 0.4 л", "180 / 220 \u20bd"),
    ("Латте", "0.3 / 0.4 л", "190 / 230 \u20bd"),
    ("Раф", "0.3 / 0.4 л", "210 / 250 \u20bd"),
    ("Американо", "0.2 / 0.3 л", "140 / 170 \u20bd"),
    ("Флэт уайт", "0.3 л", "230 \u20bd"),
]
my = cat_y + 55
for i, (name, size, price) in enumerate(items_data):
    iy = my + i * 110
    draw_rounded_rect(draw, [sx + 10, iy, sx + sw - 10, iy + 100], fill=CARD_BG, radius=14, outline=CARD_BORDER, width=1)
    draw_rounded_rect(draw, [sx + 20, iy + 10, sx + 90, iy + 80], fill=(30, 75, 75), radius=12)
    draw.text((sx + 40, iy + 30), "\u2615", fill=GOLD, font=font_screen_title)
    draw.text((sx + 105, iy + 15), name, fill=WHITE, font=font_screen_title)
    draw.text((sx + 105, iy + 48), size, fill=LIGHT_TEAL, font=font_screen_small)
    draw.text((sx + 105, iy + 70), price, fill=GOLD, font=font_screen_text)
    draw_rounded_rect(draw, [sx + sw - 110, iy + 35, sx + sw - 20, iy + 70], fill=EMERALD, radius=12, outline=GOLD, width=1)
    draw.text((sx + sw - 100, iy + 42), "Заказать", fill=GOLD, font=font_screen_small)

img.save(f"{OUT_DIR}/05_menu.png", "PNG")
print("5/6 done")


# ===== 6: Map =====
img, draw = create_base("Карта кофеен", "Найди ближайшую Arabica")
sx, sy, sw, sh = draw_phone(draw)
draw_rounded_rect(draw, [sx, sy, sx + sw, sy + 55], fill=(15, 48, 48), radius=0)
draw.text((sx + 15, sy + 12), "Кофейни рядом", fill=GOLD, font=font_screen_title)

map_y = sy + 60
map_h = 380
draw.rectangle([sx, map_y, sx + sw, map_y + map_h], fill=(18, 45, 45))
for i in range(0, sw, 60):
    draw.line([(sx + i, map_y), (sx + i, map_y + map_h)], fill=(22, 55, 55), width=1)
for i in range(0, map_h, 60):
    draw.line([(sx, map_y + i), (sx + sw, map_y + i)], fill=(22, 55, 55), width=1)
draw.line([(sx + 50, map_y + 100), (sx + sw - 50, map_y + 280)], fill=(35, 80, 80), width=3)
draw.line([(sx + 200, map_y + 30), (sx + 200, map_y + 350)], fill=(35, 80, 80), width=3)
draw.line([(sx + 100, map_y + 200), (sx + sw - 30, map_y + 200)], fill=(35, 80, 80), width=3)

for px, py2 in [(180, 150), (350, 200), (500, 120), (280, 300)]:
    draw.ellipse([sx + px - 14, map_y + py2 - 14, sx + px + 14, map_y + py2 + 14], fill=GOLD)
    draw.ellipse([sx + px - 8, map_y + py2 - 8, sx + px + 8, map_y + py2 + 8], fill=DARK)

shops = [
    ("Arabica Центральная", "ул. Ленина, 15", "300 м", "8:00\u201322:00"),
    ("Arabica Набережная", "пр. Мира, 42", "1.2 км", "7:00\u201323:00"),
    ("Arabica Парковая", "ул. Садовая, 8", "2.5 км", "8:00\u201321:00"),
]
shop_y = map_y + map_h + 15
for i, (name, addr, dist, hours) in enumerate(shops):
    cy = shop_y + i * 115
    draw_rounded_rect(draw, [sx + 10, cy, sx + sw - 10, cy + 105], fill=CARD_BG, radius=14, outline=CARD_BORDER, width=1)
    draw.text((sx + 25, cy + 10), name, fill=WHITE, font=font_screen_title)
    draw.text((sx + 25, cy + 42), addr, fill=LIGHT_TEAL, font=font_screen_text)
    draw.text((sx + 25, cy + 70), hours, fill=(120, 160, 160), font=font_screen_small)
    draw_rounded_rect(draw, [sx + sw - 110, cy + 12, sx + sw - 20, cy + 42], fill=EMERALD, radius=12, outline=GOLD, width=1)
    bbox = draw.textbbox((0, 0), dist, font=font_screen_small)
    dw = bbox[2] - bbox[0]
    draw.text((sx + sw - 65 - dw // 2, cy + 18), dist, fill=GOLD, font=font_screen_small)

img.save(f"{OUT_DIR}/06_map.png", "PNG")
print("6/6 done")

# Verify
for f in sorted(os.listdir(OUT_DIR)):
    fp = os.path.join(OUT_DIR, f)
    im = Image.open(fp)
    sz = os.path.getsize(fp)
    print(f"  {f}: {im.size}, {sz // 1024} KB")
print("\nAll 6 screenshots created!")
