import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shops/models/shop_model.dart';
import 'recount_questions_page.dart';

/// Страница выбора магазина для пересчета
class RecountShopSelectionPage extends StatefulWidget {
  const RecountShopSelectionPage({super.key});

  @override
  State<RecountShopSelectionPage> createState() => _RecountShopSelectionPageState();
}

class _RecountShopSelectionPageState extends State<RecountShopSelectionPage> {
  bool _isLoading = true;
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _loadEmployeeName();
  }

  /// Загрузить имя сотрудника
  Future<void> _loadEmployeeName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('user_name');

      setState(() {
        _employeeName = employeeName;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Ошибка загрузки имени сотрудника: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пересчет товаров'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : _employeeName == null || _employeeName!.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_off,
                            size: 80,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Требуется авторизация',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Для начала пересчета необходимо войти в систему.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Назад'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF004D40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : FutureBuilder<List<Shop>>(
                    future: Shop.loadShopsFromGoogleSheets(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              const Text(
                                'Что-то пошло не так, попробуйте позже',
                                style: TextStyle(color: Colors.white, fontSize: 18),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Назад'),
                              ),
                            ],
                          ),
                        );
                      }

                      final shops = snapshot.data ?? [];
                      if (shops.isEmpty) {
                        return const Center(
                          child: Text(
                            'Магазины не найдены',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Выберите магазин:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.85,
                                ),
                                itemCount: shops.length,
                                itemBuilder: (context, index) {
                                  final shop = shops[index];

                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RecountQuestionsPage(
                                            employeeName: _employeeName!,
                                            shopAddress: shop.address,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.5),
                                          width: 2,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(shop.icon, size: 40, color: Colors.white),
                                          const SizedBox(height: 8),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(
                                              shop.address,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
