import 'package:flutter/material.dart';
import 'menu_page.dart';

class MenuGroupsPage extends StatelessWidget {
  final List<String> groups;
  final String? selectedShop;

  const MenuGroupsPage({
    super.key,
    required this.groups,
    this.selectedShop,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Категории меню')),
      body: GridView.count(
        crossAxisCount: 2, // две плитки в ряд
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        padding: const EdgeInsets.all(12),
        childAspectRatio: 1.3, // увеличили соотношение сторон — плитки ниже
        children: groups.map((g) {
          return ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MenuPage(
                    selectedCategory: g,
                    selectedShop: selectedShop,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal[700],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
              padding: const EdgeInsets.all(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_cafe,
                  size: 20, // ↓ стало меньше
                  color: Colors.white.withOpacity(0.9),
                ),
                const SizedBox(height: 6),
                Text(
                  g,
                  style: const TextStyle(
                    fontSize: 14, // ↓ уменьшили шрифт
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
