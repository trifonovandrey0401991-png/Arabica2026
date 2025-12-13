# Установка Android SDK для Linux

## Проблема
Ошибка "could not find SDK" означает, что Android SDK не установлен или путь к нему не указан.

## Решение 1: Установка через Android Studio (рекомендуется)

1. Скачайте Android Studio с официального сайта:
   https://developer.android.com/studio

2. Установите Android Studio:
   ```bash
   # Распакуйте архив и запустите установку
   cd ~/Downloads
   unzip android-studio-*.zip
   cd android-studio/bin
   ./studio.sh
   ```

3. В Android Studio:
   - Откройте Settings/Preferences → Appearance & Behavior → System Settings → Android SDK
   - Установите Android SDK Platform-Tools и необходимые платформы
   - Запомните путь к SDK (обычно `~/Android/Sdk`)

4. Обновите `android/local.properties`:
   ```properties
   sdk.dir=/home/YOUR_USERNAME/Android/Sdk
   ```

## Решение 2: Установка через командную строку

1. Скачайте Command Line Tools:
   ```bash
   cd ~
   mkdir -p Android/Sdk
   cd Android/Sdk
   wget https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip
   unzip commandlinetools-linux-*.zip
   mkdir -p cmdline-tools/latest
   mv cmdline-tools/* cmdline-tools/latest/ 2>/dev/null || true
   ```

2. Установите SDK компоненты:
   ```bash
   export ANDROID_HOME=~/Android/Sdk
   export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
   export PATH=$PATH:$ANDROID_HOME/platform-tools
   
   sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0"
   ```

3. Обновите `android/local.properties`:
   ```properties
   sdk.dir=/root/Android/Sdk
   ```

## Решение 3: Если SDK уже установлен

Если Android SDK уже установлен, но путь не указан:

1. Найдите путь к SDK:
   ```bash
   find ~ -name "platform-tools" -type d 2>/dev/null
   ```

2. Обновите `android/local.properties` с найденным путем:
   ```properties
   sdk.dir=/путь/к/Android/Sdk
   ```

## Настройка переменных окружения (опционально)

Добавьте в `~/.bashrc` или `~/.zshrc`:
```bash
export ANDROID_HOME=~/Android/Sdk
export ANDROID_SDK_ROOT=~/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
```

Затем выполните:
```bash
source ~/.bashrc
```

## Проверка установки

После установки проверьте:
```bash
flutter doctor -v
```

Должна быть зеленая галочка напротив "Android toolchain".



