import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/job_application_model.dart';

class JobApplicationDetailPage extends StatelessWidget {
  final JobApplication application;

  const JobApplicationDetailPage({
    super.key,
    required this.application,
  });

  Future<void> _callPhone(BuildContext context) async {
    final phone = application.phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$phone');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось позвонить'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final shiftColor = application.preferredShift == 'day' ? Colors.orange : Colors.indigo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заявка на работу'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Шапка с ФИО
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF004D40).withOpacity(0.1),
                      child: Text(
                        application.fullName.isNotEmpty
                            ? application.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF004D40),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            application.fullName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormat.format(application.createdAt),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Телефон
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone, color: Color(0xFF004D40)),
                title: const Text('Телефон'),
                subtitle: Text(
                  application.phone,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () => _callPhone(context),
                  tooltip: 'Позвонить',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Желаемое время работы
            Card(
              child: ListTile(
                leading: Icon(
                  application.preferredShift == 'day'
                      ? Icons.wb_sunny
                      : Icons.nightlight_round,
                  color: shiftColor,
                ),
                title: const Text('Желаемое время работы'),
                subtitle: Text(
                  application.shiftDisplayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: shiftColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Выбранные магазины
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.store, color: Color(0xFF004D40)),
                        const SizedBox(width: 8),
                        const Text(
                          'Где хочет работать',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF004D40).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${application.shopAddresses.length} магазин(ов)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF004D40),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...application.shopAddresses.map((address) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 20,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Информация о просмотре
            if (application.isViewed)
              Card(
                color: Colors.green.shade50,
                child: ListTile(
                  leading: const Icon(Icons.visibility, color: Colors.green),
                  title: const Text('Просмотрено'),
                  subtitle: Text(
                    application.viewedAt != null
                        ? '${application.viewedBy ?? "Администратор"} • ${dateFormat.format(application.viewedAt!)}'
                        : application.viewedBy ?? 'Администратор',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _callPhone(context),
            icon: const Icon(Icons.call),
            label: const Text(
              'Позвонить кандидату',
              style: TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
