#!/bin/bash

echo "🔍 Проверка файлов системы ролей..."
echo ""

# Проверка наличия файлов
echo "1. Проверка наличия файлов:"
if [ -f "lib/role_test_page.dart" ]; then
    echo "   ✅ lib/role_test_page.dart существует"
else
    echo "   ❌ lib/role_test_page.dart НЕ НАЙДЕН"
fi

if [ -f "lib/user_role_model.dart" ]; then
    echo "   ✅ lib/user_role_model.dart существует"
else
    echo "   ❌ lib/user_role_model.dart НЕ НАЙДЕН"
fi

if [ -f "lib/user_role_service.dart" ]; then
    echo "   ✅ lib/user_role_service.dart существует"
else
    echo "   ❌ lib/user_role_service.dart НЕ НАЙДЕН"
fi

echo ""
echo "2. Проверка импортов в main_menu_page.dart:"
if grep -q "import 'role_test_page.dart';" lib/main_menu_page.dart; then
    echo "   ✅ Импорт role_test_page.dart найден"
else
    echo "   ❌ Импорт role_test_page.dart НЕ НАЙДЕН"
fi

if grep -q "import 'user_role_model.dart';" lib/main_menu_page.dart; then
    echo "   ✅ Импорт user_role_model.dart найден"
else
    echo "   ❌ Импорт user_role_model.dart НЕ НАЙДЕН"
fi

if grep -q "import 'user_role_service.dart';" lib/main_menu_page.dart; then
    echo "   ✅ Импорт user_role_service.dart найден"
else
    echo "   ❌ Импорт user_role_service.dart НЕ НАЙДЕН"
fi

echo ""
echo "3. Проверка кнопки 'Тест ролей':"
if grep -q "Тест ролей" lib/main_menu_page.dart; then
    echo "   ✅ Кнопка 'Тест ролей' найдена в коде"
    echo "   Строки с кнопкой:"
    grep -n "Тест ролей" lib/main_menu_page.dart | head -3
else
    echo "   ❌ Кнопка 'Тест ролей' НЕ НАЙДЕНА"
fi

echo ""
echo "4. Проверка метода _getMenuItems():"
if grep -q "_getMenuItems()" lib/main_menu_page.dart; then
    echo "   ✅ Метод _getMenuItems() найден"
    echo "   Вызов метода:"
    grep -n "_getMenuItems()" lib/main_menu_page.dart | head -2
else
    echo "   ❌ Метод _getMenuItems() НЕ НАЙДЕН"
fi

echo ""
echo "5. Проверка последних коммитов:"
git log --oneline -5 | grep -E "(role|Role)" || echo "   ⚠️ Коммиты с ролями не найдены в последних 5"

echo ""
echo "✅ Проверка завершена!"




