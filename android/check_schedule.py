#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
import requests
import json
from collections import defaultdict
from datetime import datetime, timedelta

# Загружаем данные
response = requests.get('https://arabica26.ru/api/work-schedule?month=2026-01')
data = response.json()
entries = data['schedule']['entries']

# Группируем по сотрудникам
employee_shifts = defaultdict(list)

for entry in entries:
    employee_shifts[entry['employeeId']].append({
        'date': entry['date'],
        'shiftType': entry['shiftType'],
        'employeeName': entry['employeeName']
    })

# Проверяем нарушения
violations = []

for emp_id, shifts in employee_shifts.items():
    # Сортируем по дате
    shifts_sorted = sorted(shifts, key=lambda x: x['date'])

    for i in range(len(shifts_sorted) - 1):
        curr = shifts_sorted[i]
        next_shift = shifts_sorted[i + 1]

        # Проверка 1: Утро после вечера
        if curr['shiftType'] == 'evening' and next_shift['shiftType'] == 'morning':
            curr_dt = datetime.fromisoformat(curr['date'])
            next_dt = datetime.fromisoformat(next_shift['date'])
            if (next_dt - curr_dt).days == 1:
                violations.append(f"❌ {curr['employeeName']}: evening {curr['date']} → morning {next_shift['date']}")

        # Проверка 2: Две смены в один день
        if curr['date'] == next_shift['date']:
            violations.append(f"❌ {curr['employeeName']}: 2 смены в один день {curr['date']}")

print("\n" + "="*60)
print("ПРОВЕРКА 24-ЧАСОВОГО ПРАВИЛА")
print("="*60 + "\n")

if violations:
    print("❌ Найдены нарушения:")
    for v in violations:
        print(f"  {v}")
else:
    print("✅ Нарушений 24-часового правила НЕ НАЙДЕНО!")
    print(f"✅ Проверено {len(employee_shifts)} сотрудников")
    print(f"✅ Проверено {len(entries)} смен")

# Статистика по сменам
print("\n" + "="*60)
print("СТАТИСТИКА РАСПРЕДЕЛЕНИЯ")
print("="*60 + "\n")

shift_counts = {}
for emp_id, shifts in employee_shifts.items():
    name = shifts[0]['employeeName']
    shift_counts[name] = len(shifts)

max_shifts = max(shift_counts.values())
min_shifts = min(shift_counts.values())
avg_shifts = sum(shift_counts.values()) / len(shift_counts)

print(f"Минимум смен: {min_shifts}")
print(f"Максимум смен: {max_shifts}")
print(f"Среднее: {avg_shifts:.1f}")
print(f"Разница: {max_shifts - min_shifts} смен")
print(f"\nРаспределение:")
from collections import Counter
distribution = Counter(shift_counts.values())
for count in sorted(distribution.keys(), reverse=True):
    print(f"  {count} смен: {distribution[count]} сотрудников")
