import 'package:flutter/material.dart';
import 'shift_handover_questions_page.dart';
import '../../envelope/pages/envelope_form_page.dart';
import '../../coffee_machine/pages/coffee_machine_form_page.dart';
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

  // Единая палитра приложения
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule,
                  color: Colors.orange,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Время для сдачи прошло',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Ожидайте следующей возможности',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gold.withOpacity(0.4)),
                    ),
                    child: const Text(
                      'Понятно',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: _gold.withOpacity(0.7),
                          strokeWidth: 3,
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Заголовок
                            const Text(
                              'Выберите тип:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.shopAddress,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13,
                              ),
                            ),

                            // Индикатор наличия pending отчёта
                            const SizedBox(height: 14),
                            _buildPendingStatusIndicator(),

                            const SizedBox(height: 24),

                            // Формирование конверта
                            _buildOptionCard(
                              title: 'Формирование конверта',
                              icon: Icons.mail_rounded,
                              description: 'Выручка, расходы, итог',
                              accentColor: const Color(0xFF43A047),
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
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'Вопросы',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Сдать смену
                            _buildOptionCard(
                              title: 'Сдать Смену',
                              icon: Icons.assignment_turned_in_rounded,
                              description: 'Ответить на вопросы по смене',
                              accentColor: _hasPendingReport() ? _gold : Colors.grey,
                              onTap: () => _onQuestionsCardTap(widget.isCurrentUserManager ? 'manager' : 'employee'),
                              isDisabled: !_hasPendingReport(),
                            ),
                            const SizedBox(height: 16),

                            // Счётчик кофемашин
                            _buildOptionCard(
                              title: 'Счётчик кофемашин',
                              icon: Icons.coffee_outlined,
                              description: 'Показания счётчиков кофемашин',
                              accentColor: _gold,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CoffeeMachineFormPage(
                                      employeeName: widget.employeeName,
                                      shopAddress: widget.shopAddress,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Сдача смены',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingStatusIndicator() {
    final hasPending = _hasPendingReport();
    final currentShift = _getCurrentShiftType();
    final shiftName = currentShift == 'morning' ? 'Утренняя смена' : 'Вечерняя смена';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasPending
            ? const Color(0xFF43A047).withOpacity(0.12)
            : Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPending
              ? const Color(0xFF43A047).withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasPending ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: hasPending ? const Color(0xFF43A047) : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            hasPending
                ? '$shiftName: можно сдать'
                : '$shiftName: время истекло',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required IconData icon,
    required String description,
    required Color accentColor,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isDisabled ? Icons.lock_rounded : Icons.chevron_right_rounded,
                color: isDisabled ? Colors.white.withOpacity(0.2) : accentColor.withOpacity(0.6),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
