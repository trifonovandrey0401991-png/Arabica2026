import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../recipes/models/recipe_model.dart';
import '../../recipes/services/recipe_service.dart';
import '../services/loyalty_service.dart';

/// Отчёт по бонусам клиентов (напитки и товары за баллы)
class FreeDrinksReportPage extends StatefulWidget {
  const FreeDrinksReportPage({super.key});

  @override
  State<FreeDrinksReportPage> createState() => _FreeDrinksReportPageState();
}

class _FreeDrinksReportPageState extends State<FreeDrinksReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<String>? _allowedShops;
  Map<String, Recipe> _recipesById = {};

  // Tab 1: За неделю
  List<Map<String, dynamic>> _weekRedemptions = [];
  bool _loadingWeek = false;
  String? _weekError;

  // Tab 2: По клиентам
  List<Map<String, dynamic>> _clientSummary = [];
  bool _loadingClients = false;
  String? _clientsError;
  final TextEditingController _clientSearchController = TextEditingController();
  String _clientSearch = '';

  // Static in-memory cache — survives widget rebuilds, resets on app restart
  static List<Map<String, dynamic>>? _cachedWeek;
  static DateTime? _cachedWeekTime;
  static List<Map<String, dynamic>>? _cachedClients;
  static DateTime? _cachedClientsTime;
  static const _cacheTtl = Duration(minutes: 5);

  bool get _weekCacheFresh =>
      _cachedWeek != null &&
      _cachedWeekTime != null &&
      DateTime.now().difference(_cachedWeekTime!) < _cacheTtl;

  bool get _clientsCacheFresh =>
      _cachedClients != null &&
      _cachedClientsTime != null &&
      DateTime.now().difference(_cachedClientsTime!) < _cacheTtl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    final allowed = await MultitenancyFilterService.getAllowedShopAddresses();
    List<Recipe> recipes = [];
    try {
      recipes = await RecipeService.getRecipes();
    } catch (e) { Logger.error('FreeDrinksReport', 'Failed to load recipes', e); }
    if (!mounted) return;

    // Show cached data immediately if fresh
    setState(() {
      _allowedShops = allowed ?? [];
      _recipesById = { for (final r in recipes) r.id: r };
      if (_weekCacheFresh) _weekRedemptions = _cachedWeek!;
      if (_clientsCacheFresh) _clientSummary = _cachedClients!;
    });

    // Load fresh data — silently (no spinner) if cache available, with spinner if not
    _loadWeek(silent: _weekCacheFresh);
    _loadClients(silent: _clientsCacheFresh);
  }

  Future<void> _loadWeek({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loadingWeek = true; _weekError = null; });
    try {
      final shops = (_allowedShops?.isNotEmpty == true) ? _allowedShops : null;
      final data = await LoyaltyService.fetchRedemptions(period: 'week', shopAddresses: shops);
      _cachedWeek = data;
      _cachedWeekTime = DateTime.now();
      if (mounted) setState(() { _weekRedemptions = data; _weekError = null; });
    } catch (e) {
      if (mounted && !silent) setState(() { _weekError = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (!silent && mounted) setState(() { _loadingWeek = false; });
    }
  }

  Future<void> _loadClients({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loadingClients = true; _clientsError = null; });
    try {
      final shops = (_allowedShops?.isNotEmpty == true) ? _allowedShops : null;
      final data = await LoyaltyService.fetchRedemptionsByClient(shopAddresses: shops);
      _cachedClients = data;
      _cachedClientsTime = DateTime.now();
      if (mounted) setState(() { _clientSummary = data; _clientsError = null; });
    } catch (e) {
      if (mounted && !silent) setState(() { _clientsError = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (!silent && mounted) setState(() { _loadingClients = false; });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _clientSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        title: const Text('Бонусы клиентов'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'За неделю'),
            Tab(text: 'По клиентам'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeekTab(),
          _buildClientsTab(),
        ],
      ),
    );
  }

  Widget _buildWeekTab() {
    if (_loadingWeek) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }
    if (_weekError != null) {
      return _buildError(_weekError!, () => _loadWeek());
    }
    if (_weekRedemptions.isEmpty) {
      return _buildEmpty('За последние 7 дней\nбонусов не выдавалось');
    }
    return RefreshIndicator(
      onRefresh: () => _loadWeek(),
      color: AppColors.emerald,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        itemCount: _weekRedemptions.length,
        itemBuilder: (context, index) {
          final r = _weekRedemptions[index];
          return _buildRedemptionCard(r);
        },
      ),
    );
  }

  Widget _buildClientsTab() {
    if (_loadingClients) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }
    if (_clientsError != null) {
      return _buildError(_clientsError!, () => _loadClients());
    }

    // Filter and sort: server already returns count DESC, we apply local search on top
    final query = _clientSearch.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _clientSummary
        : _clientSummary.where((c) {
            final name = (c['clientName'] as String? ?? '').toLowerCase();
            final phone = (c['clientPhone'] as String? ?? '').toLowerCase();
            final count = (c['count'] as int? ?? 0).toString();
            return name.contains(query) || phone.contains(query) || count == query;
          }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: TextField(
            controller: _clientSearchController,
            onChanged: (v) => setState(() { _clientSearch = v; }),
            style: TextStyle(color: Colors.white, fontSize: 14.sp),
            decoration: InputDecoration(
              hintText: 'Поиск по имени или кол-ву напитков',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 13.sp),
              prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
              suffixIcon: _clientSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                      onPressed: () => setState(() {
                        _clientSearchController.clear();
                        _clientSearch = '';
                      }),
                    )
                  : null,
              filled: true,
              fillColor: AppColors.emeraldDark,
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: const BorderSide(color: AppColors.emerald),
              ),
            ),
          ),
        ),
        // List
        Expanded(
          child: filtered.isEmpty
              ? _buildEmpty(_clientSummary.isEmpty
                  ? 'Нет данных о выдаче бонусов'
                  : 'Ничего не найдено')
              : RefreshIndicator(
                  onRefresh: () => _loadClients(),
                  color: AppColors.emerald,
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildClientRow(filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRedemptionCard(Map<String, dynamic> r) {
    final clientName = (r['clientName'] as String?)?.isNotEmpty == true
        ? r['clientName'] as String
        : _formatPhone(r['clientPhone'] as String? ?? '');
    final recipeName = r['recipeName'] as String? ?? '';
    final recipeId = r['recipeId'] as String? ?? '';
    final points = r['pointsPrice'] as int? ?? 0;
    final shopAddress = r['shopAddress'] as String? ?? '';
    final confirmedAt = _formatDate(r['confirmedAt']);
    final photoUrl = _recipesById[recipeId]?.photoUrlOrId;

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10.r),
            child: photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _recipeIconPlaceholder(),
                    errorWidget: (_, __, ___) => _recipeIconPlaceholder(),
                  )
                : _recipeIconPlaceholder(),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        recipeName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        '$points б.',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  clientName,
                  style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 11, color: Colors.white38),
                    SizedBox(width: 4),
                    Text(
                      confirmedAt,
                      style: TextStyle(color: Colors.white38, fontSize: 11.sp),
                    ),
                    if (shopAddress.isNotEmpty) ...[
                      SizedBox(width: 8),
                      Icon(Icons.location_on, size: 11, color: Colors.white38),
                      SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          shopAddress,
                          style: TextStyle(color: Colors.white38, fontSize: 11.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipeIconPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      color: const Color(0xFF00b09b).withOpacity(0.15),
      child: const Icon(Icons.local_cafe, color: Color(0xFF00b09b), size: 22),
    );
  }

  Widget _buildClientRow(Map<String, dynamic> client) {
    final name = (client['clientName'] as String?)?.isNotEmpty == true
        ? client['clientName'] as String
        : _formatPhone(client['clientPhone'] as String? ?? '');
    final phone = client['clientPhone'] as String? ?? '';
    final count = client['count'] as int? ?? 0;
    final totalPoints = client['totalPoints'] as int? ?? 0;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: () => _showClientHistory(client),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: AppColors.emerald,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        _formatPhone(phone),
                        style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00b09b).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        '$count шт.',
                        style: TextStyle(
                          color: const Color(0xFF00b09b),
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '$totalPoints б.',
                      style: TextStyle(color: AppColors.gold, fontSize: 11.sp),
                    ),
                  ],
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white30, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showClientHistory(Map<String, dynamic> client) {
    final name = (client['clientName'] as String?)?.isNotEmpty == true
        ? client['clientName'] as String
        : _formatPhone(client['clientPhone'] as String? ?? '');
    final phone = client['clientPhone'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.emeraldDark,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => _ClientHistorySheet(
        clientName: name,
        clientPhone: phone,
        recipesById: _recipesById,
      ),
    );
  }

  Widget _buildError(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            SizedBox(height: 12.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14.sp),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_cafe_outlined, color: Colors.white24, size: 64),
          SizedBox(height: 16.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 14.sp),
          ),
        ],
      ),
    );
  }

  String _formatPhone(String phone) {
    if (phone.length == 11 && phone.startsWith('7')) {
      return '+${phone[0]} ${phone.substring(1, 4)} ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr.toString()).toLocal();
      return DateFormat('dd.MM HH:mm').format(date);
    } catch (_) {
      return dateStr.toString();
    }
  }
}

// ─────────────────────────────────────────────────────
// Bottom sheet: история выдачи по одному клиенту
// ─────────────────────────────────────────────────────
class _ClientHistorySheet extends StatefulWidget {
  final String clientName;
  final String clientPhone;
  final Map<String, Recipe> recipesById;

  const _ClientHistorySheet({
    required this.clientName,
    required this.clientPhone,
    required this.recipesById,
  });

  @override
  State<_ClientHistorySheet> createState() => _ClientHistorySheetState();
}

class _ClientHistorySheetState extends State<_ClientHistorySheet> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await LoyaltyService.fetchClientRedemptionHistory(widget.clientPhone);
      if (mounted) setState(() { _history = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollController) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                widget.clientName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'История выдачи бонусов',
                style: TextStyle(color: Colors.white54, fontSize: 13.sp),
              ),
              SizedBox(height: 16.h),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.redAccent, fontSize: 13.sp),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _history.isEmpty
                    ? Center(
                        child: Text(
                          'История пуста',
                          style: TextStyle(color: Colors.white38, fontSize: 14.sp),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _history.length,
                        itemBuilder: (_, i) => _buildHistoryItem(_history[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final recipeId = item['recipeId'] as String? ?? '';
    final recipeName = item['recipeName'] as String? ?? '';
    final points = item['pointsPrice'] as int? ?? 0;
    final shopAddress = item['shopAddress'] as String? ?? '';
    final confirmedAt = _formatDate(item['confirmedAt']);
    final photoUrl = widget.recipesById[recipeId]?.photoUrlOrId;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _historyIconPlaceholder(),
                    errorWidget: (_, __, ___) => _historyIconPlaceholder(),
                  )
                : _historyIconPlaceholder(),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipeName,
                  style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Text(confirmedAt, style: TextStyle(color: Colors.white38, fontSize: 11.sp)),
                    if (shopAddress.isNotEmpty) ...[
                      Text('  ·  ', style: TextStyle(color: Colors.white24, fontSize: 11.sp)),
                      Expanded(
                        child: Text(
                          shopAddress,
                          style: TextStyle(color: Colors.white38, fontSize: 11.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Text(
            '$points б.',
            style: TextStyle(color: AppColors.gold, fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _historyIconPlaceholder() {
    return Container(
      width: 36,
      height: 36,
      color: const Color(0xFF00b09b).withOpacity(0.15),
      child: const Icon(Icons.local_cafe, color: Color(0xFF00b09b), size: 18),
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr.toString()).toLocal();
      return DateFormat('dd.MM.yy HH:mm').format(date);
    } catch (_) {
      return dateStr.toString();
    }
  }
}
