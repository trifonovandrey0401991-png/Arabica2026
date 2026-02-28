import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../models/job_application_model.dart';
import '../services/job_application_service.dart';
import 'job_application_detail_page.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  static const _cacheKey = 'job_applications';

  Future<void> _loadData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<JobApplication>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _applications = cached;
        _isLoading = false;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    _adminName = prefs.getString('user_display_name') ??
        prefs.getString('currentEmployeeName') ??
        prefs.getString('user_name') ??
        'Администратор';

    if (_applications.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      final applications = await JobApplicationService.getAll();
      if (!mounted) return;
      setState(() {
        _applications = applications;
        _isLoading = false;
      });
      // Step 3: Save to cache
      CacheManager.set(_cacheKey, applications);
    } catch (e) {
      if (!mounted) return;
      if (_applications.isEmpty) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _isLoading = true);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

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
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Заявки на работу',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _refresh,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        color: AppColors.gold,
                        backgroundColor: AppColors.emeraldDark,
                        child: _applications.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: EdgeInsets.all(16.w),
                                itemCount: _applications.length,
                                itemBuilder: (context, index) {
                                  final app = _applications[index];
                                  return _buildApplicationCard(app, dateFormat);
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inbox, size: 40, color: Colors.white.withOpacity(0.3)),
          ),
          SizedBox(height: 16),
          Text(
            'Нет заявок на работу',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationCard(JobApplication app, DateFormat dateFormat) {
    final shiftColor = app.preferredShift == 'day' ? Colors.orange : Colors.indigo[300]!;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
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

            _refresh();
          },
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        app.fullName,
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Color(app.status.colorValue).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        app.status.displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.phone, size: 16, color: Colors.white.withOpacity(0.3)),
                    SizedBox(width: 4),
                    Text(
                      app.phone,
                      style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: shiftColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
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
                          SizedBox(width: 4),
                          Text(
                            app.shiftDisplayName,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: shiftColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.store, size: 16, color: Colors.white.withOpacity(0.3)),
                    SizedBox(width: 4),
                    Text(
                      '${app.shopAddresses.length} магазин(ов)',
                      style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.3)),
                    SizedBox(width: 4),
                    Text(
                      dateFormat.format(app.createdAt),
                      style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
