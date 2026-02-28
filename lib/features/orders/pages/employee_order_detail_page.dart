import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../services/order_service.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../messenger/services/messenger_service.dart';
import '../../messenger/pages/messenger_chat_page.dart';

class EmployeeOrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> orderData;

  const EmployeeOrderDetailPage({
    super.key,
    required this.orderData,
  });

  @override
  State<EmployeeOrderDetailPage> createState() => _EmployeeOrderDetailPageState();
}

class _EmployeeOrderDetailPageState extends State<EmployeeOrderDetailPage> {
  bool _isProcessing = false;

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    if (price is num) {
      return price.toStringAsFixed(0);
    }
    return price.toString();
  }

  /// Строит виджет изображения для товара
  Widget _buildItemImage(String? photoId, String? imageUrl) {
    double size = 70;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return AppCachedImage(
        imageUrl: imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildPlaceholderImage(size),
      );
    }

    if (photoId != null && photoId.isNotEmpty) {
      return Image.asset(
        'assets/images/$photoId.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholderImage(size),
      );
    }

    return _buildPlaceholderImage(size);
  }

  Widget _buildPlaceholderImage(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Icon(
        Icons.local_cafe_rounded,
        size: 32,
        color: Colors.white.withOpacity(0.25),
      ),
    );
  }

  Future<void> _acceptOrder() async {
    if (mounted) setState(() => _isProcessing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? 'Сотрудник';

      final success = await OrderService.updateOrderStatus(
        orderId: widget.orderData['id'],
        status: 'accepted',
        acceptedBy: employeeName,
      );

      if (success && mounted) {
        final orderNumber = widget.orderData['orderNumber'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orderNumber != null
                  ? 'Заказ $orderNumber принят'
                  : 'Заказ принят',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при принятии заказа'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectOrder() async {
    final reasonController = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.cancel_outlined, color: AppColors.error, size: 24),
            ),
            SizedBox(width: 12),
            Text(
              'Причина отказа',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: TextField(
          controller: reasonController,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Укажите причину отказа',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: AppColors.gold),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Укажите причину отказа'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(context, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            ),
            child: Text('Отказать'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final employeeName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? 'Сотрудник';

      final success = await OrderService.updateOrderStatus(
        orderId: widget.orderData['id'],
        status: 'rejected',
        rejectedBy: employeeName,
        rejectionReason: reason,
      );

      if (success && mounted) {
        final orderNumber = widget.orderData['orderNumber'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orderNumber != null
                  ? 'Заказ $orderNumber отклонен'
                  : 'Заказ отклонен',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при отклонении заказа'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openClientChat() async {
    final clientPhone = (widget.orderData['clientPhone'] ?? '').toString();
    if (clientPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Телефон клиента не указан')),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final myPhone = prefs.getString('user_phone') ?? '';
    final myName = prefs.getString('employee_name') ?? prefs.getString('user_name') ?? 'Сотрудник';
    if (myPhone.isEmpty || !mounted) return;

    final clientName = (widget.orderData['clientName'] ?? 'Клиент').toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final conversation = await MessengerService.getOrCreatePrivateChat(
      phone1: myPhone,
      phone2: clientPhone,
      name1: myName,
      name2: clientName,
    );

    if (!mounted) return;
    Navigator.pop(context); // close loading

    if (conversation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Не удалось открыть чат'), backgroundColor: AppColors.error),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: myPhone,
          userName: myName,
        ),
      ),
    );
  }

  Widget _buildHeader(String? orderNumber) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white.withOpacity(0.8),
                size: 18,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              orderNumber != null
                  ? 'Заказ #$orderNumber'
                  : 'Детали заказа',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String shopAddress, String clientName, String clientPhone) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.receipt_long_rounded, color: AppColors.gold, size: 22),
              ),
              SizedBox(width: 12.w),
              Text(
                'Информация о заказе',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          _buildInfoRow(Icons.store_rounded, 'Магазин', shopAddress),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            child: Container(height: 1, color: Colors.white.withOpacity(0.06)),
          ),
          _buildInfoRow(Icons.person_rounded, 'Клиент', clientName),
          if (clientPhone.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Container(height: 1, color: Colors.white.withOpacity(0.06)),
            ),
            _buildInfoRow(Icons.phone_rounded, 'Телефон', clientPhone),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.white.withOpacity(0.35)),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.white.withOpacity(0.35),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold),
        SizedBox(width: 8.w),
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final name = item['name'] ?? 'Товар';
    final price = _formatPrice(item['price']);
    final quantity = item['quantity'] ?? 1;
    final total = _formatPrice(item['total']);
    final photoId = item['photoId'] as String?;
    final imageUrl = item['imageUrl'] as String?;

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(12.w),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: _buildItemImage(photoId, imageUrl),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                SizedBox(height: 6.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    '$price руб \u00D7 $quantity',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              '$total руб',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
                color: AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentSection(String comment) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_rounded, color: AppColors.gold, size: 20),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              comment,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.gold,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSection(dynamic totalPrice) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Итого к оплате:',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          Text(
            '${_formatPrice(totalPrice)} руб',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.night,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Написать клиенту" — верхняя строка
            GestureDetector(
              onTap: _isProcessing ? null : _openClientChat,
              child: Container(
                width: double.infinity,
                height: 46.h,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_outlined, color: Colors.white.withOpacity(0.75), size: 18),
                      SizedBox(width: 8.w),
                      Text(
                        'Написать клиенту',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 10.h),
            // "Отказать" и "Принять" — нижняя строка
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _isProcessing ? null : _rejectOrder,
                    child: Container(
                      height: 52.h,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: _isProcessing
                            ? SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.close_rounded, color: AppColors.error, size: 20),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Отказать',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: GestureDetector(
                    onTap: _isProcessing ? null : _acceptOrder,
                    child: Container(
                      height: 52.h,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                      ),
                      child: Center(
                        child: _isProcessing
                            ? SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_rounded, color: AppColors.gold, size: 20),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Принять',
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderNumber = widget.orderData['orderNumber']?.toString();
    final shopAddress = (widget.orderData['shopAddress'] ?? 'Неизвестный магазин').toString();
    final clientName = (widget.orderData['clientName'] ?? 'Клиент').toString();
    final clientPhone = (widget.orderData['clientPhone'] ?? '').toString();
    final items = widget.orderData['items'] as List<dynamic>? ?? [];
    final totalPrice = widget.orderData['totalPrice'];
    final comment = widget.orderData['comment'];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: const [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(orderNumber),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info card
                      _buildInfoCard(shopAddress, clientName, clientPhone),
                      SizedBox(height: 20.h),

                      // Items section
                      _buildSectionTitle(Icons.shopping_bag_rounded, 'Состав заказа'),
                      SizedBox(height: 12.h),
                      if (items.isEmpty)
                        Container(
                          padding: EdgeInsets.all(20.w),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          child: Center(
                            child: Text(
                              'Нет товаров',
                              style: TextStyle(color: Colors.white.withOpacity(0.4)),
                            ),
                          ),
                        )
                      else
                        ...items.map((item) => _buildItemCard(item as Map<String, dynamic>)),

                      // Comment
                      if (comment != null && comment.toString().isNotEmpty) ...[
                        SizedBox(height: 20.h),
                        _buildSectionTitle(Icons.comment_rounded, 'Комментарий'),
                        SizedBox(height: 12.h),
                        _buildCommentSection(comment.toString()),
                      ],

                      // Total
                      SizedBox(height: 20.h),
                      _buildTotalSection(totalPrice),
                      SizedBox(height: 100.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomButtons(),
    );
  }
}
