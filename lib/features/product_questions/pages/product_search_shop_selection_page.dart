import 'package:flutter/material.dart';
import '../../shops/models/shop_model.dart';
import 'product_question_input_page.dart';

class ProductSearchShopSelectionPage extends StatefulWidget {
  const ProductSearchShopSelectionPage({super.key});

  @override
  State<ProductSearchShopSelectionPage> createState() => _ProductSearchShopSelectionPageState();
}

class _ProductSearchShopSelectionPageState extends State<ProductSearchShopSelectionPage> {
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      final shops = await Shop.loadShopsFromServer();
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка загрузки магазинов: $e';
        _isLoading = false;
      });
    }
  }

  void _selectShop(Shop? shop) {
    final shopAddress = shop?.address ?? 'Вся сеть';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductQuestionInputPage(
          shopAddress: shopAddress,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск товара'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadShops,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Кнопка "Узнать во всей сети"
                    Card(
                      elevation: 4,
                      color: const Color(0xFF004D40),
                      child: ListTile(
                        leading: const Icon(Icons.store_mall_directory, color: Colors.white, size: 32),
                        title: const Text(
                          'Узнать во всей сети',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Вопрос будет отправлен всем магазинам',
                          style: TextStyle(color: Colors.white70),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                        onTap: () => _selectShop(null),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Список магазинов
                    ..._shops.map((shop) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: Icon(shop.icon, color: const Color(0xFF004D40), size: 32),
                            title: Text(
                              shop.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(shop.address),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () => _selectShop(shop),
                          ),
                        )),
                  ],
                ),
    );
  }
}



