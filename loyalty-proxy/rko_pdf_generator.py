#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Скрипт для генерации РКО PDF через reportlab с использованием координат
"""

import sys
import json
import os
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

PAGE_WIDTH, PAGE_HEIGHT = A4

# Координаты полей (настроены через интерактивный редактор)
COORDS = {
    "org_name": (86, PAGE_HEIGHT - 790),  # Организация и ИНН
    "org_address": (51, PAGE_HEIGHT - 763),  # Фактический адрес
    "doc_number": (410, PAGE_HEIGHT - 724),  # Номер документа
    "doc_date": (476, PAGE_HEIGHT - 723),  # Дата составления
    "amount_numeric": (273, PAGE_HEIGHT - 596),  # Сумма цифрами
    "fio_receiver": (240, PAGE_HEIGHT - 639),  # ФИО получателя
    "basis": (240, PAGE_HEIGHT - 615),  # Основание
    "amount_text": (0, PAGE_HEIGHT - 48),  # Сумма прописью
    "attachment": (488, PAGE_HEIGHT - 44),  # Приложение
    "head_position": (192, PAGE_HEIGHT - 551),  # Должность руководителя
    "head_name": (400, PAGE_HEIGHT - 551),  # ФИО руководителя
    "receiver_amount_text": (203, PAGE_HEIGHT - 502),  # Сумма получателя
    "date_text": (55, PAGE_HEIGHT - 469),  # Дата текстом
    "passport_info": (50, PAGE_HEIGHT - 450),  # Паспортные данные
    "passport_issuer": (221, PAGE_HEIGHT - 449),  # Выдан паспорт
    "cashier_name": (237, PAGE_HEIGHT - 423),  # ФИО кассира
}


def register_fonts():
    """Регистрирует шрифты для поддержки кириллицы"""
    font_paths = [
        '/root/.cursor/LiberationSerif-Regular.ttf',
        '/root/arabica_app/assets/fonts/LiberationSerif-Regular.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf',
    ]
    
    # Пробуем найти шрифт
    font_path = None
    for path in font_paths:
        if os.path.exists(path):
            font_path = path
            break
    
    if font_path:
        try:
            pdfmetrics.registerFont(TTFont("LiberationSerif", font_path))
            return "LiberationSerif"
        except Exception as e:
            print(f"Ошибка регистрации LiberationSerif: {e}", file=sys.stderr)
    
    # Fallback на стандартный шрифт
    return "Helvetica"


def generate_rko_pdf(output_path, template_image_path, data):
    """
    Генерирует PDF РКО с использованием фонового изображения и координат
    
    Args:
        output_path: путь для сохранения PDF
        template_image_path: путь к изображению шаблона
        data: словарь с данными для заполнения
    """
    try:
        # Регистрируем шрифт
        font_name = register_fonts()
        
        # Создаем canvas
        c = canvas.Canvas(output_path, pagesize=A4)
        
        # Рисуем фоновое изображение
        if os.path.exists(template_image_path):
            c.drawImage(template_image_path, 0, 0, width=PAGE_WIDTH, height=PAGE_HEIGHT)
        else:
            raise FileNotFoundError(f"Изображение шаблона не найдено: {template_image_path}")
        
        def put(field, text, size=10, font=font_name):
            """Помещает текст в указанное поле по координатам"""
            if field not in COORDS or not text:
                return
            x, y = COORDS[field]
            c.setFont(font, size)
            c.drawString(x, y, str(text))
        
        # Заполнение полей
        put("org_name", data.get("org_name", ""), size=10)
        put("org_address", data.get("org_address", ""), size=10)
        put("doc_number", data.get("doc_number", ""), size=10)
        put("doc_date", data.get("doc_date", ""), size=10)
        put("amount_numeric", data.get("amount_numeric", ""), size=12)
        put("fio_receiver", data.get("fio_receiver", ""), size=11)
        put("basis", data.get("basis", ""), size=11)
        put("amount_text", data.get("amount_text", ""), size=11)
        put("attachment", data.get("attachment", ""), size=10)
        put("head_position", data.get("head_position", "ИП"), size=10)
        put("head_name", data.get("head_name", ""), size=11)
        put("receiver_amount_text", data.get("receiver_amount_text", data.get("amount_text", "")), size=11)
        put("date_text", data.get("date_text", ""), size=11)
        put("passport_info", data.get("passport_info", ""), size=9)
        put("passport_issuer", data.get("passport_issuer", ""), size=9)
        put("cashier_name", data.get("cashier_name", ""), size=11)
        
        c.showPage()
        c.save()
        
        return {"success": True, "error": None}
        
    except Exception as e:
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(json.dumps({"success": False, "error": "Недостаточно аргументов. Используйте: python3 rko_pdf_generator.py <template_image_path> <output_pdf_path> <data_json>"}))
        sys.exit(1)
    
    template_image_path = sys.argv[1]
    output_pdf_path = sys.argv[2]
    data_json = sys.argv[3] if len(sys.argv) > 3 else "{}"
    
    try:
        data = json.loads(data_json)
    except json.JSONDecodeError as e:
        print(json.dumps({"success": False, "error": f"Ошибка парсинга JSON: {e}"}))
        sys.exit(1)
    
    result = generate_rko_pdf(output_pdf_path, template_image_path, data)
    print(json.dumps(result, ensure_ascii=False))

