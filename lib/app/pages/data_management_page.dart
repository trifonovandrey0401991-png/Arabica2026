import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../features/shops/pages/shops_management_page.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shifts/pages/shift_questions_management_page.dart';
import '../../features/recount/pages/recount_management_tabs_page.dart';
import '../../features/tests/pages/test_questions_management_page.dart';
import '../../features/training/pages/training_articles_management_page.dart';
import '../../features/clients/pages/clients_management_page.dart';
import '../../features/shift_handover/pages/shift_handover_questions_management_page.dart';
import '../../features/coffee_machine/pages/coffee_machine_questions_management_page.dart';
import '../../features/suppliers/pages/suppliers_management_page.dart';
import '../../features/efficiency/pages/points_settings_page.dart';
import '../../features/tasks/pages/task_management_page.dart';
import '../../features/bonuses/pages/bonus_penalty_management_page.dart';
import '../../features/data_cleanup/pages/data_cleanup_page.dart';
import '../../features/work_schedule/pages/work_schedule_page.dart';
import '../../features/ai_training/pages/ai_training_page.dart';
import '../../features/execution_chain/pages/execution_chain_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница управления данными (только для администраторов)
class DataManagementPage extends StatelessWidget {
  const DataManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                  children: [
                    _buildRow(
                      icon: Icons.storefront_outlined,
                      title: 'Магазины',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ShopsManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.people_outline_rounded,
                      title: 'Сотрудники',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => EmployeesPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.calendar_month_outlined,
                      title: 'График работы',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => WorkSchedulePage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Вопросы пересменки',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ShiftQuestionsManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.calculate_outlined,
                      title: 'Вопросы пересчёта',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => RecountManagementTabsPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.quiz_outlined,
                      title: 'Вопросы тестирования',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TestQuestionsManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Вопросы (Сдать смену)',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ShiftHandoverQuestionsManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.coffee_outlined,
                      title: 'Счётчик кофемашин',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CoffeeMachineQuestionsManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.menu_book_outlined,
                      title: 'Статьи обучения',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TrainingArticlesManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.groups_outlined,
                      title: 'Клиенты',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ClientsManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.local_shipping_outlined,
                      title: 'Поставщики',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SuppliersManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.stars_outlined,
                      title: 'Установка баллов',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PointsSettingsPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.task_alt_outlined,
                      title: 'Установить задачи',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TaskManagementPage(createdBy: 'admin')),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Премия / Штрафы',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => BonusPenaltyManagementPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.link_rounded,
                      title: 'Цепочка Выполнений',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ExecutionChainPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.psychology_outlined,
                      title: 'Обучение ИИ',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AITrainingPage()),
                      ),
                    ),
                    _buildRow(
                      icon: Icons.delete_sweep_outlined,
                      title: 'Очистка историй',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DataCleanupPage()),
                      ),
                    ),
                  ],
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
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 24.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Управление',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  /// Минималистичная строка меню
  Widget _buildRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),

                // Название
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                // Стрелка
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.4),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
