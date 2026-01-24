DBF Sync Agent
==============

Агент синхронизации товаров из DBF файла на сервер Arabica.

УСТАНОВКА
---------

1. Установите Python 3.8+ с python.org

2. Установите зависимости:
   pip install -r requirements.txt

3. Скопируйте config.example.json в config.json:
   copy config.example.json config.json

4. Отредактируйте config.json:
   - shopId: уникальный ID магазина (например: shop_1, shop_vesna)
   - shopName: название магазина
   - dbfPath: полный путь к файлу tov.dbf
   - apiKey: ключ авторизации (получить у администратора)

ЗАПУСК
------

python agent.py

Агент будет:
- Мониторить изменения в DBF файле
- Отправлять товары на сервер каждые 60 секунд
- Логировать действия в sync.log

АВТОЗАПУСК (Windows)
--------------------

1. Создайте ярлык для agent.py

2. Переместите ярлык в:
   C:\Users\<ИМЯ>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup

3. В свойствах ярлыка измените:
   - Объект: pythonw.exe "C:\путь\к\agent.py"
   - Рабочая папка: C:\путь\к\

ПОЛЯ DBF
--------

По умолчанию агент использует поля:
- KOD    -> код товара (штрих-код)
- NAME   -> название
- ГРУППА -> группа/категория
- ОСТ    -> остаток

Если в вашем DBF другие названия полей, измените секцию "fields" в config.json.

ЛОГИ
----

Логи записываются в файл sync.log рядом с agent.py.
Также логи выводятся в консоль при ручном запуске.
