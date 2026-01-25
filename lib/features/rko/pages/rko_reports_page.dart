import 'package:flutter/material.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/models/shop_model.dart';
import '../services/rko_reports_service.dart';
import 'rko_employee_reports_page.dart';
import 'rko_shop_reports_page.dart';
import 'rko_pdf_viewer_page.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../core/utils/logger.dart';

/// Главная страница отчетов по РКО с вкладками
class RKOReportsPage extends StatefulWidget {
  const RKOReportsPage({super.key});

  @override
  State<RKOReportsPage> createState() => _RKOReportsPageState();
}

class _RKOReportsPageState extends State<RKOReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Данные
  List<Employee> _employees = [];
  List<Shop> _shops = [];
  List<dynamic> _pendingRKOs = [];
  List<dynamic> _failedRKOs = [];
  bool _isLoading = true;
  String _employeeSearchQuery = '';
  String _shopSearchQuery = '';

  // Градиентные цвета для страницы
  static const _gradientColors = [Color(0xFF004D40), Color(0xFF00695C)];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.rko);
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Загружаем данные параллельно
      final results = await Future.wait([
        EmployeesPage.loadEmployeesForNotifications(),
        Shop.loadShopsFromServer(),
        RKOReportsService.getPendingRKOs(),
        RKOReportsService.getFailedRKOs(),
      ]);

      setState(() {
        _employees = results[0] as List<Employee>;
        _shops = results[1] as List<Shop>;
        _pendingRKOs = results[2] as List<dynamic>;
        _failedRKOs = results[3] as List<dynamic>;
        _isLoading = false;
      });

      Logger.success('Загружено: ${_employees.length} сотрудников, ${_shops.length} магазинов, ${_pendingRKOs.length} pending, ${_failedRKOs.length} failed');
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _gradientColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Заголовок
              _buildHeader(),
              // Вкладки
              _buildTwoRowTabs(),
              // Содержимое вкладок
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // Вкладка 0: Отчёт по сотрудникам
                          _buildEmployeesTab(),
                          // Вкладка 1: Отчёт по магазинам
                          _buildShopsTab(),
                          // Вкладка 2: Ожидают
                          _buildPendingTab(),
                          // Вкладка 3: Не прошли
                          _buildFailedTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Красивый заголовок страницы
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Отчёты по РКО',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Сотрудников: ${_employees.length}, Магазинов: ${_shops.length}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadData,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  /// Построение двухрядных вкладок
  Widget _buildTwoRowTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        children: [
          // Первый ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(0, Icons.person_rounded, 'По сотрудникам', _employees.length, Colors.blue),
              const SizedBox(width: 6),
              _buildTabButton(1, Icons.store_rounded, 'По магазинам', _shops.length, Colors.orange),
            ],
          ),
          const SizedBox(height: 6),
          // Второй ряд: 2 вкладки
          Row(
            children: [
              _buildTabButton(2, Icons.schedule, 'Ожидают', _pendingRKOs.length, Colors.amber),
              const SizedBox(width: 6),
              _buildTabButton(3, Icons.warning_amber, 'Не прошли', _failedRKOs.length, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  /// Построение одной кнопки-вкладки
  Widget _buildTabButton(int index, IconData icon, String label, int count, Color accentColor) {
    final isSelected = _tabController.index == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.animateTo(index);
            setState(() {});
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [accentColor.withOpacity(0.8), accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? accentColor : Colors.white30,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.3) : accentColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Красивый пустой стейт
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: ОТЧЁТ ПО СОТРУДНИКАМ
  // ============================================================

  Widget _buildEmployeesTab() {
    return Column(
      children: [
        // Поиск
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: Icon(Icons.search, color: _gradientColors[0]),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (value) {
                setState(() {
                  _employeeSearchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
        ),
        // Список сотрудников
        Expanded(
          child: _employees.isEmpty
              ? _buildEmptyState(
                  icon: Icons.person_off_rounded,
                  title: 'Сотрудники не найдены',
                  subtitle: 'Добавьте сотрудников для просмотра их РКО',
                  color: Colors.blue,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _employees.length,
                  itemBuilder: (context, index) {
                    final employee = _employees[index];

                    // Фильтрация по поисковому запросу
                    if (_employeeSearchQuery.isNotEmpty) {
                      final name = employee.name.toLowerCase();
                      if (!name.contains(_employeeSearchQuery)) {
                        return const SizedBox.shrink();
                      }
                    }

                    return _buildEmployeeCard(employee);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Employee employee) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final normalizedName = employee.name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RKOEmployeeDetailPage(
                  employeeName: normalizedName,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Аватар
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade300, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (employee.position != null && employee.position!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          employee.position!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Стрелка
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.blue,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: ОТЧЁТ ПО МАГАЗИНАМ
  // ============================================================

  Widget _buildShopsTab() {
    return Column(
      children: [
        // Поиск
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск магазина...',
                prefixIcon: Icon(Icons.search, color: _gradientColors[0]),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (value) {
                setState(() {
                  _shopSearchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
        ),
        // Список магазинов
        Expanded(
          child: _shops.isEmpty
              ? _buildEmptyState(
                  icon: Icons.store_mall_directory_outlined,
                  title: 'Магазины не найдены',
                  subtitle: 'Добавьте магазины для просмотра их РКО',
                  color: Colors.orange,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _shops.length,
                  itemBuilder: (context, index) {
                    final shop = _shops[index];

                    // Фильтрация по поисковому запросу
                    if (_shopSearchQuery.isNotEmpty) {
                      final address = shop.address.toLowerCase();
                      if (!address.contains(_shopSearchQuery)) {
                        return const SizedBox.shrink();
                      }
                    }

                    return _buildShopCard(shop);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShopCard(Shop shop) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RKOShopDetailPage(
                  shopAddress: shop.address,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade300, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.store_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // Адрес
                Expanded(
                  child: Text(
                    shop.address,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Стрелка
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: ОЖИДАЮТ
  // ============================================================

  Widget _buildPendingTab() {
    if (_pendingRKOs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Нет ожидающих РКО',
        subtitle: 'Все РКО обработаны',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pendingRKOs.length,
      itemBuilder: (context, index) {
        final rko = _pendingRKOs[index];
        return _buildPendingRKOCard(rko);
      },
    );
  }

  Widget _buildPendingRKOCard(dynamic rko) {
    final employeeName = rko['employeeName']?.toString() ?? '';
    final shopName = rko['shopName']?.toString() ?? '';
    final shopAddress = rko['shopAddress']?.toString() ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final rkoType = rko['rkoType']?.toString() ?? '';
    final shiftType = rko['shiftType']?.toString() ?? '';
    final deadline = rko['deadline']?.toString() ?? '';

    // Определяем что показывать в заголовке
    final title = employeeName.isNotEmpty ? employeeName : shopName;
    final subtitle = employeeName.isNotEmpty ? shopAddress : shopAddress;
    final shiftLabel = shiftType == 'morning' ? 'Утренняя смена' : 'Вечерняя смена';

    // Форматируем дедлайн
    String deadlineText = '';
    if (deadline.isNotEmpty) {
      try {
        final dt = DateTime.parse(deadline);
        deadlineText = 'до ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade300, Colors.amber.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.schedule,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (shiftType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: shiftType == 'morning'
                                ? Colors.orange.withOpacity(0.1)
                                : Colors.indigo.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            shiftLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: shiftType == 'morning' ? Colors.orange[800] : Colors.indigo[800],
                            ),
                          ),
                        ),
                      if (deadlineText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            deadlineText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.red[800],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Сумма
            if (amount.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$amount руб.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ВКЛАДКА: НЕ ПРОШЛИ
  // ============================================================

  Widget _buildFailedTab() {
    if (_failedRKOs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.thumb_up,
        title: 'Нет отклонённых РКО',
        subtitle: 'Все РКО успешно обработаны',
        color: Colors.green,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _failedRKOs.length,
      itemBuilder: (context, index) {
        final rko = _failedRKOs[index];
        return _buildFailedRKOCard(rko);
      },
    );
  }

  Widget _buildFailedRKOCard(dynamic rko) {
    final employeeName = rko['employeeName'] ?? '';
    final shopAddress = rko['shopAddress'] ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final rkoType = rko['rkoType'] ?? '';
    final reason = rko['reason'] ?? 'Причина не указана';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Иконка с предупреждением
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade400, Colors.red.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shopAddress,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (rkoType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rkoType,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ОТКЛОНЕНО',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Сумма
            if (amount.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$amount руб.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
