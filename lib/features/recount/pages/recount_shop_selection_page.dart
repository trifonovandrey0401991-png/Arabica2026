import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
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
  String? _employeePhone;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  /// Загрузить данные сотрудника
  Future<void> _loadEmployeeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Используем user_display_name (короткое имя "Андрей В") вместо user_name (полное имя)
      final employeeName = prefs.getString('user_display_name') ?? prefs.getString('user_name');
      // Проверяем оба ключа для телефона (userPhone для сотрудников, user_phone для клиентов)
      final employeePhone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

      Logger.debug('Загружены данные: displayName=$employeeName, phone=$employeePhone');

      setState(() {
        _employeeName = employeeName;
        _employeePhone = employeePhone;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных сотрудника', e);
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
                              child: ListView.builder(
                                itemCount: shops.length,
                                itemBuilder: (context, index) {
                                  final shop = shops[index];

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Material(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => RecountQuestionsPage(
                                                employeeName: _employeeName!,
                                                shopAddress: shop.address,
                                                employeePhone: _employeePhone,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.5),
                                              width: 2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const ShopIcon(size: 56),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Text(
                                                  shop.address,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right,
                                                color: Colors.white70,
                                                size: 28,
                                              ),
                                            ],
                                          ),
                                        ),
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
