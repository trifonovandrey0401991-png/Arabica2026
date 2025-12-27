# Инструкция по очистке Android кэша

Если скрипт не запускается, выполните команды вручную:

## Шаг 1: Очистка Flutter
```powershell
flutter clean
```

## Шаг 2: Очистка Android кэша
```powershell
cd android
Remove-Item -Recurse -Force .gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\.cxx -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\.externalNativeBuild -ErrorAction SilentlyContinue
cd ..
```

## Шаг 3: Очистка корневой папки build
```powershell
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
```

## Шаг 4: Очистка файлов Flutter
```powershell
Remove-Item -Recurse -Force .flutter-plugins -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .flutter-plugins-dependencies -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
```

## Шаг 5: Получение зависимостей
```powershell
flutter pub get
```

## Шаг 6: Запуск
```powershell
flutter run
```

## Если проблема сохраняется:

### Вариант 1: Очистка глобального Gradle кэша
```powershell
$gradleCache = "$env:USERPROFILE\.gradle\caches"
Remove-Item -Recurse -Force "$gradleCache\transforms-*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$gradleCache\modules-*" -ErrorAction SilentlyContinue
```

### Вариант 2: Проверка версии Flutter
```powershell
flutter --version
flutter doctor
```

### Вариант 3: Пересоздание Android платформы
```powershell
flutter create --platforms=android .
```







