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
        backgroundColor: AppColors.night,
        appBar: AppBar(
          title: Text('Задачи', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.emeraldDark,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.gold),
          bottom: TabBar(
            indicatorColor: AppColors.gold,
            labelColor: AppColors.gold,
            unselectedLabelColor: Colors.white.withOpacity(0.5),
            tabs: const [
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
