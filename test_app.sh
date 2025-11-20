#!/bin/bash
# Скрипт для проверки Flutter приложения (Linux/Mac)
# Использование: ./test_app.sh

echo "=== Проверка Flutter приложения Arabica ==="
echo ""

# 1. Проверка версии Flutter
echo "1. Проверка версии Flutter..."
flutter --version
if [ $? -ne 0 ]; then
    echo "ОШИБКА: Flutter не установлен или не найден в PATH"
    exit 1
fi
echo ""

# 2. Проверка окружения
echo "2. Проверка окружения Flutter..."
flutter doctor
echo ""

# 3. Проверка зависимостей
echo "3. Проверка зависимостей проекта..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "ОШИБКА: Не удалось установить зависимости"
    exit 1
fi
echo ""

# 4. Анализ кода
echo "4. Анализ кода..."
flutter analyze
echo ""

# 5. Проверка подключенных устройств
echo "5. Проверка доступных устройств..."
flutter devices
echo ""

# 6. Сборка в режиме отладки (без запуска)
echo "6. Проверка сборки приложения..."
echo "Выберите платформу для проверки:"
echo "  [1] Android (APK)"
echo "  [2] Web"
echo "  [3] Windows"
echo "  [4] Linux"
echo "  [5] Пропустить сборку"
echo ""
read -p "Введите номер (1-5): " choice

case $choice in
    1)
        echo "Сборка Android APK..."
        flutter build apk --debug
        ;;
    2)
        echo "Сборка Web..."
        flutter build web
        ;;
    3)
        echo "Сборка Windows..."
        flutter build windows
        ;;
    4)
        echo "Сборка Linux..."
        flutter build linux
        ;;
    5)
        echo "Сборка пропущена"
        ;;
    *)
        echo "Неверный выбор, сборка пропущена"
        ;;
esac

echo ""
echo "=== Проверка завершена ==="
echo ""
echo "Для запуска приложения используйте:"
echo "  flutter run                    # Запуск на подключенном устройстве"
echo "  flutter run -d chrome          # Запуск в браузере Chrome"
echo "  flutter run -d windows         # Запуск на Windows"
echo "  flutter run -d linux           # Запуск на Linux"
echo "  flutter run -d android         # Запуск на Android"



