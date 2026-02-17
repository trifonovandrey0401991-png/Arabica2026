import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'regular_task_points_settings_page.dart';
import 'recurring_task_points_settings_page.dart';

class TaskPointsSettingsPage extends StatelessWidget {
  const TaskPointsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Задачи'),
          backgroundColor: AppColors.primaryGreen,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Обычные'),
              Tab(text: 'Циклические'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            RegularTaskPointsSettingsPage(),
            RecurringTaskPointsSettingsPage(),
          ],
        ),
      ),
    );
  }
}
