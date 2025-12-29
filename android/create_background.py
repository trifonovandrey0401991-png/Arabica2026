from PIL import Image, ImageDraw

# Создаем изображение 1920x1080 с градиентом
width, height = 1920, 1080
image = Image.new('RGB', (width, height))
draw = ImageDraw.Draw(image)

# Создаем простой градиент от темно-зеленого к более светлому
for y in range(height):
    # Градиент от #004D40 к #00695C
    r = 0
    g = int(77 + (105 - 77) * y / height)
    b = int(64 + (92 - 64) * y / height)
    draw.line([(0, y), (width, y)], fill=(r, g, b))

# Сохраняем
image.save('../assets/images/arabica_background.png')
print('Background image created successfully!')
