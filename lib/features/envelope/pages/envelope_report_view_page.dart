import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/envelope_report_model.dart';
import '../services/envelope_report_service.dart';
import '../../../core/utils/logger.dart';
import '../../employees/services/user_role_service.dart';

class EnvelopeReportViewPage extends StatefulWidget {
  final EnvelopeReport report;
  final bool isAdmin;

  const EnvelopeReportViewPage({
    super.key,
    required this.report,
    this.isAdmin = false,
  });

  @override
  State<EnvelopeReportViewPage> createState() => _EnvelopeReportViewPageState();
}

class _EnvelopeReportViewPageState extends State<EnvelopeReportViewPage> {
  late EnvelopeReport _report;
  bool _isLoading = false;
  int _selectedRating = 5;

  static const _primaryColor = Color(0xFF004D40);

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  Future<void> _confirmReport() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердить отчет'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Выберите оценку:'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final rating = index + 1;
                    return IconButton(
                      icon: Icon(
                        rating <= _selectedRating
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () {
                        setDialogState(() => _selectedRating = rating);
                      },
                    );
                  }),
                ),
                Text(
                  'Оценка: $_selectedRating',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);
      try {
        // Получаем имя текущего авторизованного пользователя (администратора)
        // ВАЖНО: используем user_display_name/user_employee_name, которые НЕ перезаписываются
        // при просмотре отчетов других сотрудников (в отличие от currentEmployeeName)
        String adminName = 'Администратор';
        final prefs = await SharedPreferences.getInstance();

        // Приоритет: user_employee_name -> user_display_name -> user_name -> loadUserRole
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
          // Пробуем загрузить из кэша ролей
          final roleData = await UserRoleService.loadUserRole();
          if (roleData != null && roleData.displayName.isNotEmpty) {
            adminName = roleData.displayName;
          }
        }

        Logger.debug('📝 Подтверждение отчета администратором: $adminName');
        Logger.debug('   user_employee_name: $userEmployeeName');
        Logger.debug('   user_display_name: $userDisplayName');
        Logger.debug('   user_name: $userName');

        final updated = await EnvelopeReportService.confirmReport(
          _report.id,
          adminName,
          _selectedRating,
        );
        if (updated != null && mounted) {
          setState(() => _report = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Отчет подтвержден!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        Logger.error('Ошибка подтверждения отчета', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteReport() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить отчет?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final success = await EnvelopeReportService.deleteReport(_report.id);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Отчет удален'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        Logger.error('Ошибка удаления отчета', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showPhoto(String? url, String title) {
    if (url == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => const SizedBox(
                  height: 200,
                  child: Center(child: Icon(Icons.error, size: 48)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчет конверта'),
        backgroundColor: _primaryColor,
        actions: [
          if (widget.isAdmin && _report.status == 'pending')
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _isLoading ? null : _deleteReport,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _buildHeader(),
                  const SizedBox(height: 16),

                  // Status
                  _buildStatusCard(),
                  const SizedBox(height: 16),

                  // ООО Section
                  _buildOOOSection(),
                  const SizedBox(height: 16),

                  // ИП Section
                  _buildIPSection(),
                  const SizedBox(height: 16),

                  // Total
                  _buildTotalCard(),
                  const SizedBox(height: 24),

                  // Confirm button
                  if (widget.isAdmin && _report.status == 'pending')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _confirmReport,
                        icon: const Icon(Icons.check),
                        label: const Text('Подтвердить отчет'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: _primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _report.employeeName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.store, color: Colors.grey, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_report.shopAddress)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _report.shiftType == 'morning'
                      ? Icons.wb_sunny
                      : Icons.nights_stay,
                  color: _report.shiftType == 'morning'
                      ? Colors.orange
                      : Colors.indigo,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('${_report.shiftTypeText} смена'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey, size: 20),
                const SizedBox(width: 8),
                Text(_formatDate(_report.createdAt)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final isConfirmed = _report.status == 'confirmed';
    final isExpired = _report.isExpired;

    return Card(
      color: isConfirmed
          ? Colors.green[50]
          : (isExpired ? Colors.red[50] : Colors.orange[50]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isConfirmed
                  ? Icons.check_circle
                  : (isExpired ? Icons.warning : Icons.pending),
              color: isConfirmed
                  ? Colors.green
                  : (isExpired ? Colors.red : Colors.orange),
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isExpired && !isConfirmed
                        ? 'Просрочен'
                        : _report.statusText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isConfirmed
                          ? Colors.green
                          : (isExpired ? Colors.red : Colors.orange),
                    ),
                  ),
                  if (isConfirmed && _report.confirmedByAdmin != null) ...[
                    Text('Подтвердил: ${_report.confirmedByAdmin}'),
                    if (_report.confirmedAt != null)
                      Text(_formatDate(_report.confirmedAt!)),
                  ],
                  if (_report.rating != null)
                    Row(
                      children: [
                        const Text('Оценка: '),
                        ...List.generate(5, (index) {
                          return Icon(
                            index < _report.rating!
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 18,
                          );
                        }),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOOOSection() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'ООО',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_report.oooZReportPhotoUrl != null)
                  TextButton.icon(
                    onPressed: () => _showPhoto(
                      _report.oooZReportPhotoUrl,
                      'Z-отчет ООО',
                    ),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('Z-отчет'),
                  ),
                if (_report.oooEnvelopePhotoUrl != null)
                  TextButton.icon(
                    onPressed: () => _showPhoto(
                      _report.oooEnvelopePhotoUrl,
                      'Конверт ООО',
                    ),
                    icon: const Icon(Icons.mail, size: 16),
                    label: const Text('Конверт'),
                  ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Выручка:', '${_report.oooRevenue.toStringAsFixed(0)} руб'),
            _buildInfoRow('Наличные:', '${_report.oooCash.toStringAsFixed(0)} руб'),
            const Divider(),
            _buildInfoRow(
              'В конверте:',
              '${_report.oooEnvelopeAmount.toStringAsFixed(0)} руб',
              isBold: true,
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIPSection() {
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'ИП',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_report.ipZReportPhotoUrl != null)
                  TextButton.icon(
                    onPressed: () => _showPhoto(
                      _report.ipZReportPhotoUrl,
                      'Z-отчет ИП',
                    ),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('Z-отчет'),
                  ),
                if (_report.ipEnvelopePhotoUrl != null)
                  TextButton.icon(
                    onPressed: () => _showPhoto(
                      _report.ipEnvelopePhotoUrl,
                      'Конверт ИП',
                    ),
                    icon: const Icon(Icons.mail, size: 16),
                    label: const Text('Конверт'),
                  ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Выручка:', '${_report.ipRevenue.toStringAsFixed(0)} руб'),
            _buildInfoRow('Наличные:', '${_report.ipCash.toStringAsFixed(0)} руб'),
            if (_report.expenses.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Расходы:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...(_report.expenses.map((e) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('- ${e.supplierName}'),
                          if (e.comment != null && e.comment!.isNotEmpty)
                            Text(
                              e.comment!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '-${e.amount.toStringAsFixed(0)} руб',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ))),
              const SizedBox(height: 4),
              _buildInfoRow(
                'Итого расходов:',
                '-${_report.totalExpenses.toStringAsFixed(0)} руб',
                color: Colors.red,
              ),
            ],
            const Divider(),
            _buildInfoRow(
              'В конверте:',
              '${_report.ipEnvelopeAmount.toStringAsFixed(0)} руб',
              isBold: true,
              color: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Card(
      color: _primaryColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ИТОГО В КОНВЕРТАХ:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_report.totalEnvelopeAmount.toStringAsFixed(0)} руб',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
