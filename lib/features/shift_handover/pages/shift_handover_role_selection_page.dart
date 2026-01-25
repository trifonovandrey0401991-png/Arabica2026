import 'package:flutter/material.dart';
import 'shift_handover_questions_page.dart';
import '../../envelope/pages/envelope_form_page.dart';
import '../services/pending_shift_handover_service.dart';
import '../models/pending_shift_handover_report_model.dart';
import '../../../core/utils/logger.dart';

/// Страница выбора типа сдачи смены
class ShiftHandoverRoleSelectionPage extends StatefulWidget {
  final String employeeName;
  final String shopAddress;
  final bool isCurrentUserManager;

  const ShiftHandoverRoleSelectionPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
    this.isCurrentUserManager = false,
  });

  @override
  State<ShiftHandoverRoleSelectionPage> createState() => _ShiftHandoverRoleSelectionPageState();
}

class _ShiftHandoverRoleSelectionPageState extends State<ShiftHandoverRoleSelectionPage> {
  List<PendingShiftHandoverReport> _pendingReports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingReports();
  }

  Future<void> _loadPendingReports() async {
    try {
      final reports = await PendingShiftHandoverService.getPendingReports();
      if (mounted) {
        setState(() {
          _pendingReports = reports;
          _isLoading = false;
        });
      }
      Logger.info('Загружено pending отчётов: ${reports.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки pending отчётов', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Определить текущий тип смены (утро/вечер) по времени
  String _getCurrentShiftType() {
    final hour = DateTime.now().hour;
    // Утренняя смена: до 14:00, вечерняя: после 14:00
    return hour < 14 ? 'morning' : 'evening';
  }

  /// Проверить есть ли pending отчёт для данного магазина и текущей смены
  bool _hasPendingReport() {
    final currentShift = _getCurrentShiftType();
    final shopNormalized = widget.shopAddress.toLowerCase().trim();

    for (final report in _pendingReports) {
      final reportShop = report.shopAddress.toLowerCase().trim();
      if (reportShop == shopNormalized && report.shiftType == currentShift) {
        return true;
      }
    }
    return false;
  }

  /// Показать диалог об отсутствии pending отчёта
  void _showNoPendingDialog() {
    final currentShift = _getCurrentShiftType();
    final shiftName = currentShift == 'morning' ? 'утренней' : 'вечерней';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            const Text('Сдача смены недоступна'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Для $shiftName смены на этом магазине нет активного отчёта.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Возможно, время сдачи смены истекло и отчёт перешёл в "Не в срок".',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  /// Обработчик нажатия на карточку с вопросами
  void _onQuestionsCardTap(String targetRole) {
    // Проверяем есть ли pending отчёт
    if (!_hasPendingReport()) {
      _showNoPendingDialog();
      return;
    }

    // Есть pending отчёт - переходим к вопросам
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftHandoverQuestionsPage(
          employeeName: widget.employeeName,
          shopAddress: widget.shopAddress,
          targetRole: targetRole,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сдача смены'),
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
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      const Text(
                        'Выберите тип:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.shopAddress,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),

                      // Индикатор наличия pending отчёта
                      const SizedBox(height: 12),
                      _buildPendingStatusIndicator(),

                      const SizedBox(height: 24),

                      // Формирование конверта - главная опция (всегда доступна)
                      _buildOptionCard(
                        context,
                        title: 'Формирование конверта',
                        icon: Icons.mail,
                        description: 'Выручка, расходы, итог',
                        color: Colors.green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EnvelopeFormPage(
                                employeeName: widget.employeeName,
                                shopAddress: widget.shopAddress,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Divider
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Вопросы',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Сотрудник
                      _buildOptionCard(
                        context,
                        title: 'Сотрудник',
                        icon: Icons.person,
                        description: 'Вопросы для сотрудников',
                        color: _hasPendingReport() ? Colors.blue : Colors.grey,
                        onTap: () => _onQuestionsCardTap('employee'),
                        isDisabled: !_hasPendingReport(),
                      ),
                      // Заведующая - показываем только для сотрудников с флагом isManager
                      if (widget.isCurrentUserManager) ...[
                        const SizedBox(height: 16),
                        _buildOptionCard(
                          context,
                          title: 'Заведующая',
                          icon: Icons.supervisor_account,
                          description: 'Вопросы для заведующих',
                          color: _hasPendingReport() ? Colors.purple : Colors.grey,
                          onTap: () => _onQuestionsCardTap('manager'),
                          isDisabled: !_hasPendingReport(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPendingStatusIndicator() {
    final hasPending = _hasPendingReport();
    final currentShift = _getCurrentShiftType();
    final shiftName = currentShift == 'morning' ? 'Утренняя смена' : 'Вечерняя смена';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hasPending
            ? Colors.green.withOpacity(0.2)
            : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasPending ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasPending ? Icons.check_circle : Icons.warning_amber,
            color: hasPending ? Colors.green : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            hasPending
                ? '$shiftName: можно сдать'
                : '$shiftName: время истекло',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String description,
    required Color color,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isDisabled ? 0.6 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isDisabled ? Icons.lock : Icons.chevron_right,
                color: color,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
