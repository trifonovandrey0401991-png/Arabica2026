import 'package:flutter/material.dart';

/// Модель магазина
class Shop {
  final String name;
  final String address;
  final IconData icon;

  Shop({
    required this.name,
    required this.address,
    required this.icon,
  });

  /// Получить список всех магазинов
  static List<Shop> getShops() {
    return [
      Shop(
        name: 'Арабика Пятигорск',
        address: 'г. Пятигорск, ул. Ленина, 10',
        icon: Icons.store,
      ),
      Shop(
        name: 'Арабика Ессентуки',
        address: 'г. Ессентуки, ул. Мира, 5',
        icon: Icons.store_mall_directory,
      ),
      Shop(
        name: 'Арабика Кисловодск',
        address: 'г. Кисловодск, пр. Мира, 15',
        icon: Icons.local_cafe,
      ),
      Shop(
        name: 'Арабика Железноводск',
        address: 'г. Железноводск, ул. Лермонтова, 8',
        icon: Icons.coffee,
      ),
      Shop(
        name: 'Арабика Минеральные Воды',
        address: 'г. Минеральные Воды, ул. Советская, 20',
        icon: Icons.restaurant,
      ),
      Shop(
        name: 'Арабика Ставрополь',
        address: 'г. Ставрополь, пр. Карла Маркса, 42',
        icon: Icons.shopping_bag,
      ),
    ];
  }
}

