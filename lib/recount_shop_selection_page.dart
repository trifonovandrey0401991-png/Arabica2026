import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shop_model.dart';
import 'shift_report_model.dart';
import 'recount_questions_page.dart';

/// Страница выбора магазина для пересчета (с проверкой пересменки)
class RecountShopSelectionPage extends StatefulWidget {
  const RecountShopSelectionPage({super.key});

  @override
  State<RecountShopSelectionPage> createState() => _RecountShopSelectionPageState();
}

class _RecountShopSelectionPageState extends State<RecountShopSelectionPage> {
  bool _isChecking = true;
  bool _hasShiftReport = false;
  String? _employeeName;
  String? _lastShopAddress;

  @override
  void initState() {
    super.initState();
    _checkShiftReport();
  }

  /// Проверить, есть ли отчет пересменки за последние 12 часов
  Future<void> _checkShiftReport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('user_name');
      
      if (employeeName == null || employeeName.isEmpty) {
        setState(() {
          _isChecking = false;
          _hasShiftReport = false;
        });
        return;
      }

      setState(() {
        _employeeName = employeeName;
      });

      // Загружаем все отчеты пересменки
      final allReports = await ShiftReport.loadAllReports();
      
      // Фильтруем по сотруднику и времени (последние 12 часов)
      final now = DateTime.now();
      final twelveHoursAgo = now.subtract(const Duration(hours: 12));
      
      final recentReports = allReports.where((report) {
        return report.employeeName == employeeName &&
               report.createdAt.isAfter(twelveHoursAgo);
      }).toList();

      if (recentReports.isNotEmpty) {
        // Берем последний отчет
        recentReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final lastReport = recentReports.first;
        
        setState(() {
          _hasShiftReport = true;
          _lastShopAddress = lastReport.shopAddress;
        });
      } else {
        setState(() {
          _hasShiftReport = false;
        });
      }
    } catch (e) {
      print('❌ Ошибка проверки пересменки: $e');
      setState(() {
        _hasShiftReport = false;
      });
    } finally {
      setState(() {
        _isChecking = false;
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
        child: _isChecking
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : !_hasShiftReport
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 80,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Пересчет недоступен',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Для начала пересчета необходимо сначала пройти пересменку.\n\nПересменка должна быть пройдена в течение последних 12 часов.',
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

                      // Если есть магазин из последней пересменки, показываем его первым
                      final sortedShops = List<Shop>.from(shops);
                      if (_lastShopAddress != null) {
                        final lastShopIndex = sortedShops.indexWhere(
                          (s) => s.address == _lastShopAddress,
                        );
                        if (lastShopIndex != -1) {
                          final lastShop = sortedShops.removeAt(lastShopIndex);
                          sortedShops.insert(0, lastShop);
                        }
                      }

                      return Column(
                        children: [
                          // Информация о последней пересменке
                          if (_lastShopAddress != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withOpacity(0.5),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Пересменка пройдена',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Магазин: $_lastShopAddress',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Список магазинов
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: sortedShops.length,
                              itemBuilder: (context, index) {
                                final shop = sortedShops[index];
                                final isLastShop = shop.address == _lastShopAddress;
                                
                                return GestureDetector(
                                  onTap: () {
                                    if (_employeeName != null) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RecountQuestionsPage(
                                            employeeName: _employeeName!,
                                            shopAddress: shop.address,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isLastShop
                                          ? Colors.green.withOpacity(0.3)
                                          : Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isLastShop
                                            ? Colors.green.withOpacity(0.7)
                                            : Colors.white.withOpacity(0.5),
                                        width: isLastShop ? 3 : 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (isLastShop)
                                          const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 20,
                                          ),
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
                      );
                    },
                  ),
      ),
    );
  }
}







