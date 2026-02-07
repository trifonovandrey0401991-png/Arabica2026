import 'package:flutter/material.dart';
import '../models/coffee_machine_report_model.dart';
import '../services/coffee_machine_report_service.dart';
import '../../../core/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../employees/services/user_role_service.dart';

/// Детальный просмотр отчёта по счётчику кофемашин
class CoffeeMachineReportViewPage extends StatefulWidget {
  final CoffeeMachineReport report;

  const CoffeeMachineReportViewPage({super.key, required this.report});

  @override
  State<CoffeeMachineReportViewPage> createState() => _CoffeeMachineReportViewPageState();
}

class _CoffeeMachineReportViewPageState extends State<CoffeeMachineReportViewPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  bool _isConfirming = false;
  int _selectedRating = 0;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    return Scaffold(
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
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoCard(report),
                      const SizedBox(height: 16),
                      _buildReadingsSection(report),
                      const SizedBox(height: 16),
                      _buildComputerSection(report),
                      const SizedBox(height: 16),
                      _buildVerificationSection(report),
                      if (report.status == 'pending') ...[
                        const SizedBox(height: 24),
                        _buildConfirmSection(),
                      ],
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Icon(Icons.coffee_outlined, color: _gold, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Отчёт по счётчику',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          // Статус
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.report.statusText,
              style: TextStyle(color: _getStatusColor(), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (widget.report.status) {
      case 'confirmed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'failed':
      case 'expired':
        return Colors.red;
      default:
        return _gold;
    }
  }

  Widget _buildInfoCard(CoffeeMachineReport report) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.person, 'Сотрудник', report.employeeName),
          _buildInfoRow(Icons.store, 'Магазин', report.shopAddress),
          _buildInfoRow(Icons.schedule, 'Смена', report.shiftTypeText),
          _buildInfoRow(Icons.calendar_today, 'Дата', report.date),
          if (report.confirmedByAdmin != null)
            _buildInfoRow(Icons.verified, 'Проверил', report.confirmedByAdmin!),
          if (report.rating != null)
            _buildInfoRow(Icons.star, 'Оценка', '${report.rating}/5'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.4), size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingsSection(CoffeeMachineReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Показания машин',
          style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ...report.readings.map((reading) => _buildReadingCard(reading)),
      ],
    );
  }

  Widget _buildReadingCard(CoffeeMachineReading reading) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.coffee, color: _gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reading.machineName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Text(
                '${reading.confirmedNumber}',
                style: TextStyle(color: _gold, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (reading.wasManuallyEdited && reading.aiReadNumber != null) ...[
            const SizedBox(height: 6),
            Text(
              'ИИ распознал: ${reading.aiReadNumber} (исправлено вручную)',
              style: TextStyle(color: Colors.orange.withOpacity(0.7), fontSize: 11),
            ),
          ],
          if (reading.photoUrl != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                '${ApiConstants.serverUrl}${reading.photoUrl}',
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  color: Colors.white.withOpacity(0.04),
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComputerSection(CoffeeMachineReport report) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.computer, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Компьютер',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Text(
                report.computerNumber.toStringAsFixed(2),
                style: const TextStyle(color: Colors.blue, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (report.computerPhotoUrl != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                '${ApiConstants.serverUrl}${report.computerPhotoUrl}',
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  color: Colors.white.withOpacity(0.04),
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerificationSection(CoffeeMachineReport report) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: report.hasDiscrepancy
            ? Colors.orange.withOpacity(0.1)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: report.hasDiscrepancy
              ? Colors.orange.withOpacity(0.3)
              : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Сумма машин', style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text('+${report.sumOfMachines}', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Компьютер', style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text(report.computerNumber.toStringAsFixed(2), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Итого', style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                (report.computerNumber + report.sumOfMachines).toStringAsFixed(2),
                style: TextStyle(
                  color: report.hasDiscrepancy ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                report.hasDiscrepancy ? Icons.warning_amber_rounded : Icons.check_circle,
                color: report.hasDiscrepancy ? Colors.orange : Colors.green,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                report.hasDiscrepancy
                    ? 'Не сходится: ${report.discrepancyAmount.toStringAsFixed(2)}'
                    : 'Счётчик сходится!',
                style: TextStyle(
                  color: report.hasDiscrepancy ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Оценка', style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          // Рейтинг
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starNum = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selectedRating = starNum),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    starNum <= _selectedRating ? Icons.star : Icons.star_border,
                    color: _gold,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // Кнопки
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isConfirming ? null : _rejectReport,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Отклонить', style: TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isConfirming || _selectedRating == 0 ? null : _confirmReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isConfirming
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Подтвердить', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReport() async {
    setState(() => _isConfirming = true);
    try {
      String adminName = 'Администратор';
      final prefs = await SharedPreferences.getInstance();
      final userEmployeeName = prefs.getString('user_employee_name');
      final userDisplayName = prefs.getString('user_display_name');
      final userName = prefs.getString('user_name');
      if (userEmployeeName != null && userEmployeeName.isNotEmpty) {
        adminName = userEmployeeName;
      } else if (userDisplayName != null && userDisplayName.isNotEmpty) {
        adminName = userDisplayName;
      } else if (userName != null && userName.isNotEmpty) {
        adminName = userName;
      } else {
        final roleData = await UserRoleService.loadUserRole();
        if (roleData != null && roleData.displayName.isNotEmpty) {
          adminName = roleData.displayName;
        }
      }
      final result = await CoffeeMachineReportService.confirmReport(
        widget.report.id,
        adminName,
        _selectedRating,
      );

      if (!mounted) return;
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отчёт подтверждён'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка подтверждения'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Future<void> _rejectReport() async {
    setState(() => _isConfirming = true);
    try {
      String adminName = 'Администратор';
      final prefs = await SharedPreferences.getInstance();
      final userEmployeeName = prefs.getString('user_employee_name');
      final userDisplayName = prefs.getString('user_display_name');
      final userName = prefs.getString('user_name');
      if (userEmployeeName != null && userEmployeeName.isNotEmpty) {
        adminName = userEmployeeName;
      } else if (userDisplayName != null && userDisplayName.isNotEmpty) {
        adminName = userDisplayName;
      } else if (userName != null && userName.isNotEmpty) {
        adminName = userName;
      } else {
        final roleData = await UserRoleService.loadUserRole();
        if (roleData != null && roleData.displayName.isNotEmpty) {
          adminName = roleData.displayName;
        }
      }
      final result = await CoffeeMachineReportService.rejectReportWithPush(
        id: widget.report.id,
        adminName: adminName,
        employeePhone: '',
        comment: 'Отклонено',
      );

      if (!mounted) return;
      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отчёт отклонён'), backgroundColor: Colors.orange),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }
}
