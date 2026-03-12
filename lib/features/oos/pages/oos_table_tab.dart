import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/oos_table_model.dart';
import '../services/oos_service.dart';
import '../services/oos_pdf_service.dart';
import '../widgets/oos_stock_cell.dart';

/// Table tab: interactive stock table (products x shops)
class OosTableTab extends StatefulWidget {
  const OosTableTab({super.key});

  @override
  State<OosTableTab> createState() => _OosTableTabState();
}

class _OosTableTabState extends State<OosTableTab>
    with AutomaticKeepAliveClientMixin {
  List<OosTableRow> _rows = [];
  List<OosShopInfo> _shops = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _dataVerticalScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Sync vertical scroll between fixed column and data area
    _verticalScrollController.addListener(() {
      if (_dataVerticalScrollController.hasClients &&
          _dataVerticalScrollController.offset != _verticalScrollController.offset) {
        _dataVerticalScrollController.jumpTo(_verticalScrollController.offset);
      }
    });
    _dataVerticalScrollController.addListener(() {
      if (_verticalScrollController.hasClients &&
          _verticalScrollController.offset != _dataVerticalScrollController.offset) {
        _verticalScrollController.jumpTo(_dataVerticalScrollController.offset);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _dataVerticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await OosService.getTable();
      if (!mounted) return;
      setState(() {
        _rows = result.rows;
        _shops = result.shops;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки данных';
        _isLoading = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;

    setState(() => _isExporting = true);
    try {
      await OosPdfService.previewTablePdf(context: context, rows: _rows, shops: _shops);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка создания PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.white60, fontSize: 15.sp)),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Text(
            'Нет товаров с нулевым остатком.\n\nОтметьте товары во вкладке «Настройка» и дождитесь синхронизации данных.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 15.sp),
          ),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.gold,
          child: _buildTable(),
        ),
        // PDF export button
        Positioned(
          right: 16.w,
          bottom: 16.h + MediaQuery.of(context).padding.bottom,
          child: FloatingActionButton(
            onPressed: _isExporting ? null : _exportPdf,
            backgroundColor: AppColors.gold,
            child: _isExporting
                ? SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.night,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf, color: AppColors.night),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final borderColor = AppColors.emerald.withOpacity(0.3);
    final cellHeight = 44.h;
    final headerHeight = 56.h;

    return Padding(
      padding: EdgeInsets.only(bottom: 80.h),
      child: Row(
        children: [
          // Fixed left column: product names
          SizedBox(
            width: 160.w,
            child: Column(
              children: [
                // Header
                Container(
                  height: headerHeight,
                  decoration: BoxDecoration(
                    color: AppColors.emeraldDark,
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Text(
                    'Товар',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.sp,
                    ),
                  ),
                ),
                // Rows
                Expanded(
                  child: ListView.builder(
                    controller: _verticalScrollController,
                    itemCount: _rows.length,
                    itemExtent: cellHeight,
                    itemBuilder: (context, index) {
                      return Container(
                        height: cellHeight,
                        decoration: BoxDecoration(
                          color: AppColors.night,
                          border: Border(
                            bottom: BorderSide(color: borderColor, width: 0.5),
                            left: BorderSide(color: borderColor, width: 0.5),
                            right: BorderSide(color: borderColor, width: 0.5),
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        child: Text(
                          _rows[index].productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 12.sp),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Scrollable right part: shop columns
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _shops.length * 74.w,
                child: Column(
                  children: [
                    // Header row
                    SizedBox(
                      height: headerHeight,
                      child: Row(
                        children: _shops.map((shop) {
                          return Container(
                            width: 74.w,
                            height: headerHeight,
                            decoration: BoxDecoration(
                              color: AppColors.emeraldDark,
                              border: Border.all(color: borderColor, width: 0.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8.w,
                                  height: 8.w,
                                  margin: EdgeInsets.only(bottom: 2.h),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: shop.hasData && !shop.isStale
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 2.w),
                                  child: Text(
                                    shop.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    // Data rows
                    Expanded(
                      child: ListView.builder(
                        controller: _dataVerticalScrollController,
                        itemCount: _rows.length,
                        itemExtent: cellHeight,
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          return SizedBox(
                            height: cellHeight,
                            child: Row(
                              children: _shops.map((shop) {
                                final stock = row.shopStocks[shop.id];
                                return Container(
                                  width: 74.w,
                                  height: cellHeight,
                                  decoration: BoxDecoration(
                                    color: AppColors.night,
                                    border: Border.all(color: borderColor, width: 0.5),
                                  ),
                                  child: OosStockCell(stock: stock),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
