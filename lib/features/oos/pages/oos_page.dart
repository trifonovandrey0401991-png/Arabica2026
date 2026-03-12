import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import 'oos_table_tab.dart';
import 'oos_report_tab.dart';
import 'oos_settings_tab.dart';

/// Main OOS page with 3 tabs: Table, Report, Settings
class OosPage extends StatefulWidget {
  const OosPage({super.key});

  @override
  State<OosPage> createState() => _OosPageState();
}

class _OosPageState extends State<OosPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Column(
        children: [
          _buildAppBar(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                OosTableTab(),
                OosReportTab(),
                OosSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8.h,
        left: 16.w,
        right: 16.w,
        bottom: 8.h,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.emeraldDark, AppColors.emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              'OOS — Наличие товаров',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.emeraldDark,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.gold,
        indicatorWeight: 3,
        labelColor: AppColors.gold,
        unselectedLabelColor: Colors.white60,
        labelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 14.sp),
        tabs: const [
          Tab(text: 'Таблица'),
          Tab(text: 'Отчёт'),
          Tab(text: 'Настройка'),
        ],
      ),
    );
  }
}
