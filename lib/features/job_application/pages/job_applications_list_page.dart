import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/job_application_model.dart';
import '../services/job_application_service.dart';
import 'job_application_detail_page.dart';

class JobApplicationsListPage extends StatefulWidget {
  const JobApplicationsListPage({super.key});

  @override
  State<JobApplicationsListPage> createState() => _JobApplicationsListPageState();
}

class _JobApplicationsListPageState extends State<JobApplicationsListPage> {
  List<JobApplication> _applications = [];
  bool _isLoading = true;
  String _adminName = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _adminName = prefs.getString('employeeName') ?? prefs.getString('name') ?? 'Администратор';

    final applications = await JobApplicationService.getAll();
    setState(() {
      _applications = applications;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заявки на работу'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _applications.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _applications.length,
                      itemBuilder: (context, index) {
                        final app = _applications[index];
                        return _buildApplicationCard(app, dateFormat);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Нет заявок на работу',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationCard(JobApplication app, DateFormat dateFormat) {
    final shiftColor = app.preferredShift == 'day' ? Colors.orange : Colors.indigo;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          // Отмечаем как просмотренную, если ещё не просмотрена
          if (!app.isViewed) {
            await JobApplicationService.markAsViewed(app.id, _adminName);
          }

          if (!mounted) return;

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => JobApplicationDetailPage(application: app),
            ),
          );

          // Обновляем список после возврата
          _refresh();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      app.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Бейдж статуса
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Color(app.status.colorValue),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      app.status.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.phone,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    app.phone,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: shiftColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          app.preferredShift == 'day'
                              ? Icons.wb_sunny
                              : Icons.nightlight_round,
                          size: 16,
                          color: shiftColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          app.shiftDisplayName,
                          style: TextStyle(
                            fontSize: 13,
                            color: shiftColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.store,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${app.shopAddresses.length} магазин(ов)',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateFormat.format(app.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
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
}
