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
    final items = _buildItems(context);

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
                child: GridView.count(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8.w,
                  mainAxisSpacing: 8.h,
                  padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
                  children: items,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildItems(BuildContext context) {
    return [
      _buildTile(
        context,
        icon: Icons.storefront_outlined,
        label: 'Магазины',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopsManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.people_outline_rounded,
        label: 'Сотрудники',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeesPage())),
      ),
      _buildTile(
        context,
        icon: Icons.calendar_month_outlined,
        label: 'График',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkSchedulePage())),
      ),
      _buildTile(
        context,
        icon: Icons.swap_horiz_rounded,
        label: 'Пересменка',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftQuestionsManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.calculate_outlined,
        label: 'Пересчёт',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecountManagementTabsPage())),
      ),
      _buildTile(
        context,
        icon: Icons.quiz_outlined,
        label: 'Тесты',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TestQuestionsManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.check_circle_outline_rounded,
        label: 'Сдать смену',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftHandoverQuestionsManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.coffee_outlined,
        label: 'Кофемашины',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CoffeeMachineQuestionsManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.menu_book_outlined,
        label: 'Обучение',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingArticlesManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.groups_outlined,
        label: 'Клиенты',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.local_shipping_outlined,
        label: 'Поставщики',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SuppliersManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.stars_outlined,
        label: 'Баллы',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PointsSettingsPage())),
      ),
      _buildTile(
        context,
        icon: Icons.task_alt_outlined,
        label: 'Задачи',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskManagementPage(createdBy: 'admin'))),
      ),
      _buildTile(
        context,
        icon: Icons.account_balance_wallet_outlined,
        label: 'Премии',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BonusPenaltyManagementPage())),
      ),
      _buildTile(
        context,
        icon: Icons.link_rounded,
        label: 'Цепочки',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExecutionChainPage())),
      ),
      _buildTile(
        context,
        icon: Icons.psychology_outlined,
        label: 'Обуч. ИИ',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AITrainingPage())),
      ),
      _buildTile(
        context,
        icon: Icons.delete_sweep_outlined,
        label: 'Очистка',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DataCleanupPage())),
      ),
    ];
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14.r),
        splashColor: Colors.white.withOpacity(0.12),
        highlightColor: Colors.white.withOpacity(0.06),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            color: Colors.white.withOpacity(0.07),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
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
              SizedBox(height: 6.h),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
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
}
