import 'package:flutter/material.dart';
import '../models/shift_transfer_model.dart';
import '../models/work_schedule_model.dart';
import '../services/shift_transfer_service.dart';
import '../../../core/utils/logger.dart';

/// Страница заявок на передачу смен (для раздела Отчёты)
class ShiftTransferRequestsPage extends StatefulWidget {
  const ShiftTransferRequestsPage({super.key});

  @override
  State<ShiftTransferRequestsPage> createState() => _ShiftTransferRequestsPageState();
}

class _ShiftTransferRequestsPageState extends State<ShiftTransferRequestsPage> {
  List<ShiftTransferRequest> _notifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final notifications = await ShiftTransferService.getAdminRequests();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки заявок', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заявки на смены'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Нет заявок на передачу смен',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Здесь появятся заявки, требующие вашего одобрения',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final request = _notifications[index];
                      return _buildNotificationCard(request);
                    },
                  ),
                ),
    );
  }

  Widget _buildNotificationCard(ShiftTransferRequest request) {
    final isUnread = !request.isReadByAdmin;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isUnread ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isUnread
            ? const BorderSide(color: Colors.orange, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (isUnread) {
            await ShiftTransferService.markAsRead(request.id, isAdmin: true);
            _loadNotifications();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с индикатором непрочитанного
              Row(
                children: [
                  if (isUnread)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      'Заявка на передачу смены',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isUnread ? Colors.orange[800] : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Ожидает одобрения',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Информация о передаче
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Передаёт:',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.fromEmployeeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          request.acceptedBy.length > 1 ? 'Принявшие:' : 'Принимает:',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        if (request.acceptedBy.length > 1)
                          Text(
                            '${request.acceptedBy.length} чел.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.orange[700],
                            ),
                            textAlign: TextAlign.right,
                          )
                        else
                          Text(
                            request.acceptedBy.isNotEmpty
                                ? request.acceptedBy.first.employeeName
                                : (request.acceptedByEmployeeName ?? 'Неизвестно'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // Список принявших (если несколько)
              if (request.acceptedBy.length > 1) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people, size: 16, color: Colors.orange[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Готовы принять смену:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...request.acceptedBy.map((accepted) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                accepted.employeeName,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Детали смены
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      Icons.calendar_today,
                      'Дата:',
                      '${request.shiftDate.day}.${request.shiftDate.month.toString().padLeft(2, '0')}.${request.shiftDate.year}',
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      Icons.access_time,
                      'Смена:',
                      request.shiftType.label,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      Icons.store,
                      'Магазин:',
                      request.shopName.isNotEmpty ? request.shopName : request.shopAddress,
                    ),
                  ],
                ),
              ),

              // Комментарий
              if (request.comment != null && request.comment!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.comment, size: 18, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.comment!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[900],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Кнопки действий
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _declineRequest(request),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Отклонить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveRequest(request),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Одобрить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _approveRequest(ShiftTransferRequest request) async {
    // Если несколько принявших - показать диалог выбора
    if (request.acceptedBy.length > 1) {
      await _showSelectEmployeeDialog(request);
      return;
    }

    // Если один принявший - стандартный диалог подтверждения
    final employeeName = request.acceptedBy.isNotEmpty
        ? request.acceptedBy.first.employeeName
        : (request.acceptedByEmployeeName ?? 'Неизвестно');
    final employeeId = request.acceptedBy.isNotEmpty
        ? request.acceptedBy.first.employeeId
        : request.acceptedByEmployeeId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Одобрить заявку?'),
        content: SingleChildScrollView(
          child: Text(
            'Смена ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
            'будет передана от ${request.fromEmployeeName} к $employeeName.\n\n'
            'График будет обновлен автоматически.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Одобрить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.approveRequest(
        request.id,
        selectedEmployeeId: employeeId,
      );
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Заявка одобрена, график обновлен'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка одобрения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Диалог выбора сотрудника при множественном принятии
  Future<void> _showSelectEmployeeDialog(ShiftTransferRequest request) async {
    final selectedEmployee = await showDialog<AcceptedByEmployee>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите сотрудника'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Смену ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
                'готовы взять ${request.acceptedBy.length} сотрудника.\n\n'
                'Выберите кому передать смену:',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              ...request.acceptedBy.map((accepted) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => Navigator.pop(context, accepted),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.green[100],
                          child: Icon(Icons.person, color: Colors.green[700], size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            accepted.employeeName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              )),
              const SizedBox(height: 8),
              Text(
                'Остальным сотрудникам придёт уведомление об отклонении.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (selectedEmployee == null) return;

    // Подтверждение выбора
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтвердите выбор'),
        content: SingleChildScrollView(
          child: Text(
            'Смена ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
            'будет передана от ${request.fromEmployeeName} к ${selectedEmployee.employeeName}.\n\n'
            'Остальные ${request.acceptedBy.length - 1} сотрудника получат уведомление об отклонении.\n\n'
            'График будет обновлен автоматически.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Подтвердить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.approveRequest(
        request.id,
        selectedEmployeeId: selectedEmployee.employeeId,
      );
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Смена передана ${selectedEmployee.employeeName}'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка одобрения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _declineRequest(ShiftTransferRequest request) async {
    // Формируем текст о принявших
    String acceptedText;
    if (request.acceptedBy.length > 1) {
      final names = request.acceptedBy.map((a) => a.employeeName).join(', ');
      acceptedText = '$names (${request.acceptedBy.length} чел.)';
    } else if (request.acceptedBy.isNotEmpty) {
      acceptedText = request.acceptedBy.first.employeeName;
    } else {
      acceptedText = request.acceptedByEmployeeName ?? 'Неизвестно';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить заявку?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Заявка на передачу смены ${request.shiftDate.day}.${request.shiftDate.month} '
                'от ${request.fromEmployeeName} будет отклонена.',
              ),
              if (request.acceptedBy.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Следующие сотрудники получат уведомление об отклонении:',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...request.acceptedBy.map((a) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text('• ${a.employeeName}', style: const TextStyle(fontSize: 13)),
                )),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Принявший: $acceptedText',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Отклонить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.declineRequest(request.id);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Заявка отклонена'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await _loadNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка отклонения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
