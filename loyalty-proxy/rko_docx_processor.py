#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Скрипт для редактирования шаблона РКО .docx и конвертации в PDF
"""

import sys
import json
import os
from docx import Document
from datetime import datetime

def process_rko_template(template_path, output_path, data):
    """
    Обрабатывает шаблон РКО .docx и заменяет поля
    
    Args:
        template_path: путь к шаблону .docx
        output_path: путь для сохранения отредактированного .docx
        data: словарь с данными для замены
    """
    try:
        # Загружаем шаблон
        doc = Document(template_path)
        
        # Заменяем поля в параграфах
        for para in doc.paragraphs:
            text = para.text
            
            # Номер документа
            if '173' in text:
                text = text.replace('173', str(data.get('doc_number', '')))
            
            # Дата составления
            if '02.12.2025' in text:
                text = text.replace('02.12.2025', data.get('date', ''))
            
            # ФИО сотрудника
            if 'Бородина Ирина Валентиновна' in text:
                text = text.replace('Бородина Ирина Валентиновна', data.get('employee_name', ''))
            
            # Тип РКО
            if 'Зароботная плата' in text:
                text = text.replace('Зароботная плата', data.get('rko_type', ''))
            elif 'Зароботная' in text:
                # Заменяем только если есть "плата" рядом
                if 'плата' in text:
                    text = text.replace('Зароботная', data.get('rko_type', '').split()[0] if data.get('rko_type') else 'Зароботная')
                    text = text.replace('плата', data.get('rko_type', '').split()[1] if data.get('rko_type') and len(data.get('rko_type', '').split()) > 1 else 'плата')
            
            # Сумма прописью
            if 'одна тысяча рублей 00 копеек' in text:
                text = text.replace('одна тысяча рублей 00 копеек', data.get('amount_words', ''))
            
            # Адрес магазина (полный)
            if 'Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )' in text:
                text = text.replace('Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', data.get('shop_address', ''))
            elif 'Лермонтов,пр' in text and 'Лермонтова 1стр1' in text:
                # Заменяем части адреса
                text = text.replace('Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', data.get('shop_address', ''))
            
            # Директор и ИНН (полный)
            if 'Горовой Роман Владимирович ИНН: 263201995651' in text:
                text = text.replace('Горовой Роман Владимирович ИНН: 263201995651', data.get('director_inn', ''))
            elif 'Горовой Роман Владимирович' in text and 'ИНН:' in text:
                # Заменяем имя директора
                text = text.replace('Горовой Роман Владимирович', data.get('director_name', ''))
                # Заменяем ИНН
                if '263201995651' in text:
                    text = text.replace('263201995651', data.get('inn', ''))
            
            # Паспортные данные
            if '0724' in text:
                text = text.replace('0724', data.get('passport_series', ''))
            if '248651' in text:
                text = text.replace('248651', data.get('passport_number', ''))
            if 'ГУ МВД РОССИИ ПО СТАВРОПОЛЬСКОМУ КРАЮ' in text:
                text = text.replace('ГУ МВД РОССИИ ПО СТАВРОПОЛЬСКОМУ КРАЮ', data.get('passport_issued', ''))
            if '11.04.2025' in text and 'Дата выдачи' in text:
                text = text.replace('11.04.2025', data.get('passport_date', ''))
            
            para.text = text
        
        # Заменяем поля в таблицах
        # Таблица 1: Номер документа и дата
        if len(doc.tables) > 1:
            table1 = doc.tables[1]
            if len(table1.rows) > 1:
                # Номер документа
                if len(table1.rows[1].cells) > 0:
                    cell = table1.rows[1].cells[0]
                    if '173' in cell.text:
                        cell.text = cell.text.replace('173', str(data.get('doc_number', '')))
                
                # Дата
                if len(table1.rows[1].cells) > 1:
                    cell = table1.rows[1].cells[1]
                    if '02.12.2025' in cell.text:
                        cell.text = cell.text.replace('02.12.2025', data.get('date', ''))
        
        # Таблица 2: Сумма
        if len(doc.tables) > 2:
            table2 = doc.tables[2]
            if len(table2.rows) > 2:
                if len(table2.rows[2].cells) > 3:
                    cell = table2.rows[2].cells[3]
                    if '1000' in cell.text:
                        cell.text = cell.text.replace('1000', str(data.get('amount', '')))
        
        # Таблица 0: Директор, ИНН, адрес
        if len(doc.tables) > 0:
            table0 = doc.tables[0]
            for row in table0.rows:
                for cell in row.cells:
                    cell_text = cell.text
                    # Директор и ИНН (полный)
                    if 'Горовой Роман Владимирович ИНН: 263201995651' in cell_text:
                        cell.text = cell_text.replace('Горовой Роман Владимирович ИНН: 263201995651', data.get('director_inn', ''))
                    elif 'Горовой Роман Владимирович' in cell_text:
                        cell.text = cell_text.replace('Горовой Роман Владимирович', data.get('director_name', ''))
                    if '263201995651' in cell_text:
                        cell.text = cell_text.replace('263201995651', data.get('inn', ''))
                    
                    # Адрес (в той же ячейке, после директора)
                    if 'Фактический адрес: Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )' in cell_text:
                        cell.text = cell_text.replace('Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', data.get('shop_address', ''))
                    elif 'Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )' in cell_text:
                        cell.text = cell_text.replace('Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', data.get('shop_address', ''))
        
        # Дополнительные замены в параграфах
        for para in doc.paragraphs:
            text = para.text
            
            # Адрес магазина (в параграфе "Фактический адрес")
            if 'Фактический адрес' in text:
                # Заменяем адрес после "Фактический адрес:"
                if 'Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )' in text:
                    text = text.replace('Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', data.get('shop_address', ''))
                elif 'Лермонтов,пр' in text:
                    # Находим и заменяем адрес
                    import re
                    pattern = r'Лермонтов,пр[^\n]*Остановке[^\)]*\)'
                    if re.search(pattern, text):
                        text = re.sub(pattern, data.get('shop_address', ''), text)
            
            # Короткое имя директора (Горовой Р. В.)
            if 'Горовой Р. В.' in text:
                # Извлекаем короткое имя из полного
                director_short = data.get('director_short_name', '')
                if director_short:
                    text = text.replace('Горовой Р. В.', director_short)
            
            # Дата в "Получил" (2 декабря 2025 г.)
            if '2 декабря 2025 г.' in text:
                date_words = data.get('date_words', '')
                if date_words:
                    text = text.replace('2 декабря 2025 г.', date_words)
            elif 'декабря 2025' in text:
                # Более общий паттерн
                import re
                pattern = r'\d+\s+декабря\s+\d+\s+г\.'
                date_words = data.get('date_words', '')
                if date_words:
                    text = re.sub(pattern, date_words, text)
            
            para.text = text
        
        # Сохраняем отредактированный документ
        doc.save(output_path)
        return True, None
        
    except Exception as e:
        return False, str(e)


def convert_docx_to_pdf(docx_path, pdf_path):
    """
    Конвертирует .docx в PDF используя LibreOffice
    
    Args:
        docx_path: путь к .docx файлу
        pdf_path: путь для сохранения PDF
    """
    try:
        import subprocess
        
        # Используем LibreOffice для конвертации
        cmd = [
            'libreoffice',
            '--headless',
            '--convert-to', 'pdf',
            '--outdir', os.path.dirname(pdf_path) or '.',
            docx_path
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            # LibreOffice создает PDF с тем же именем, но расширением .pdf
            generated_pdf = docx_path.replace('.docx', '.pdf')
            if os.path.exists(generated_pdf):
                # Переименовываем в нужное имя
                if generated_pdf != pdf_path:
                    os.rename(generated_pdf, pdf_path)
                return True, None
            else:
                return False, "PDF файл не был создан"
        else:
            return False, f"Ошибка конвертации: {result.stderr}"
            
    except FileNotFoundError:
        return False, "LibreOffice не установлен. Установите: apt-get install libreoffice"
    except subprocess.TimeoutExpired:
        return False, "Таймаут конвертации"
    except Exception as e:
        return False, str(e)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(json.dumps({'success': False, 'error': 'Недостаточно аргументов'}))
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == 'process':
        # Обработка шаблона
        if len(sys.argv) < 5:
            print(json.dumps({'success': False, 'error': 'Недостаточно аргументов для process'}))
            sys.exit(1)
        
        template_path = sys.argv[2]
        output_path = sys.argv[3]
        data_json = sys.argv[4]
        
        try:
            data = json.loads(data_json)
            success, error = process_rko_template(template_path, output_path, data)
            
            if success:
                print(json.dumps({'success': True, 'output_path': output_path}))
            else:
                print(json.dumps({'success': False, 'error': error}))
        except Exception as e:
            print(json.dumps({'success': False, 'error': str(e)}))
    
    elif command == 'convert':
        # Конвертация в PDF
        if len(sys.argv) < 4:
            print(json.dumps({'success': False, 'error': 'Недостаточно аргументов для convert'}))
            sys.exit(1)
        
        docx_path = sys.argv[2]
        pdf_path = sys.argv[3]
        
        success, error = convert_docx_to_pdf(docx_path, pdf_path)
        
        if success:
            print(json.dumps({'success': True, 'pdf_path': pdf_path}))
        else:
            print(json.dumps({'success': False, 'error': error}))
    
    else:
        print(json.dumps({'success': False, 'error': f'Неизвестная команда: {command}'}))

