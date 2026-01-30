import 'package:flutter/material.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../../shared/providers/order_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../menu/pages/menu_page.dart';
import 'orders_page.dart';
import '../../../core/utils/logger.dart';

/// Страница корзины
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  /// Заглушка для товара без фото
  Widget _buildNoPhotoPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF004D40).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.local_cafe_rounded,
        size: 32,
        color: Color(0xFF004D40),
      ),
    );
  }

  /// Строит виджет изображения для товара в корзине
  Widget _buildCartItemImage(MenuItem item) {
    if (item.hasNetworkPhoto) {
      return Image.network(
        item.imageUrl!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox(
            width: 60,
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (_, __, ___) => _buildNoPhotoPlaceholder(),
      );
    } else if (item.photoId.isNotEmpty) {
      final imagePath = 'assets/images/${item.photoId}.jpg';
      return Image.asset(
        imagePath,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildNoPhotoPlaceholder(),
      );
    } else {
      return _buildNoPhotoPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Корзина'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Темно-бирюзовый фон (fallback)
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6, // Прозрачность фона для хорошей видимости логотипа
          ),
        ),
        child: ListenableBuilder(
        listenable: CartProvider.of(context),
        builder: (context, _) {
          final cart = CartProvider.of(context);
          
          if (cart.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Корзина пуста',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Список товаров
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: cart.items.length,
                  itemBuilder: (context, index) {
                    final cartItem = cart.items[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Фото товара
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _buildCartItemImage(cartItem.menuItem),
                              ),
                              const SizedBox(width: 12),
                              // Название и цена
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cartItem.menuItem.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${cartItem.menuItem.price} руб. × ${cartItem.quantity} = ${cartItem.totalPrice.toStringAsFixed(0)} руб.',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Кнопки количества
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: () => cart.decreaseQuantity(cartItem),
                                    color: const Color(0xFF004D40),
                                    iconSize: 24,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${cartItem.quantity}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => cart.increaseQuantity(cartItem),
                                    color: const Color(0xFF004D40),
                                    iconSize: 24,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => cart.removeItem(cartItem),
                                    color: Colors.red,
                                    iconSize: 24,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Итого и кнопка оформления
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Итого:',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${cart.totalPrice.toStringAsFixed(0)} руб.',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF004D40),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Две кнопки: Заказать и Комментарий к заказу
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                _showPickupTimeDialog(context, cart, null);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF004D40),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Заказать',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _showCommentDialogWithOrder(context, cart);
                              },
                              icon: const Icon(
                                Icons.message_outlined,
                                size: 20,
                              ),
                              label: const Text(
                                'Комментарий',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF004D40),
                                side: const BorderSide(color: Color(0xFF004D40), width: 2),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
        },
      ),
        ),
    );
  }

  /// Диалог оформления заказа (не используется, оставлен для совместимости)
  void _showOrderDialog(BuildContext context, CartProvider cart) {
    final orderProvider = OrderProvider.of(context);
    String? comment;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            'Оформление заказа',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Кнопка "Комментарий к заказу"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _showCommentDialog(builderContext, comment, (newComment) {
                      setState(() {
                        comment = newComment;
                      });
                    });
                  },
                  icon: const Icon(Icons.comment_outlined),
                  label: Text(
                    comment == null || comment!.isEmpty
                        ? 'Указать комментарий'
                        : 'Изменить комментарий',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (comment != null && comment!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          comment!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Кнопка "Заказать"
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await orderProvider.createOrder(
                        cart.items,
                        cart.totalPrice,
                        comment: comment,
                        shopAddress: cart.selectedShopAddress,
                      );
                      
                      // Получаем последний созданный заказ
                      final newOrder = orderProvider.orders.first;
                      
                      // Отправляем уведомления сотрудникам
                      if (builderContext.mounted) {
                        try {
                          // Загружаем список сотрудников
                          final employees = await EmployeesPage.loadEmployeesForNotifications();
                          if (builderContext.mounted) {
                            await NotificationService.notifyNewOrder(
                              context,
                              newOrder,
                              employees,
                            );
                          }
                        } catch (e) {
                          Logger.warning('Ошибка отправки уведомлений: $e');
                          // Все равно отправляем базовое уведомление
                          if (builderContext.mounted) {
                            await NotificationService.notifyNewOrder(
                              context,
                              newOrder,
                              [],
                            );
                          }
                        }
                      }

                      cart.clear();
                      if (builderContext.mounted) {
                        Navigator.of(dialogContext).pop();
                        Navigator.of(context).pop(); // Закрываем корзину
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Заказ успешно оформлен!'),
                            backgroundColor: Color(0xFF004D40),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (builderContext.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ошибка создания заказа: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Заказать',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Диалог выбора времени получения заказа
  void _showPickupTimeDialog(BuildContext context, CartProvider cart, String? comment) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text(
          'Через сколько заберёте заказ?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTimeOption(context, dialogContext, cart, comment, 5),
            const SizedBox(height: 8),
            _buildTimeOption(context, dialogContext, cart, comment, 10),
            const SizedBox(height: 8),
            _buildTimeOption(context, dialogContext, cart, comment, 15),
            const SizedBox(height: 8),
            _buildTimeOption(context, dialogContext, cart, comment, 30),
          ],
        ),
      ),
    );
  }

  /// Кнопка выбора времени
  Widget _buildTimeOption(
    BuildContext context,
    BuildContext dialogContext,
    CartProvider cart,
    String? comment,
    int minutes,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          Navigator.of(dialogContext).pop();
          await _createOrderWithPickupTime(context, cart, comment, minutes);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF004D40),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          '$minutes мин',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Создать заказ с указанным временем получения
  Future<void> _createOrderWithPickupTime(
    BuildContext context,
    CartProvider cart,
    String? comment,
    int pickupMinutes,
  ) async {
    try {
      final orderProvider = OrderProvider.of(context);

      // Добавляем время получения в комментарий
      final pickupComment = 'Заберу через $pickupMinutes мин';
      final fullComment = comment != null && comment.isNotEmpty
          ? '$comment\n$pickupComment'
          : pickupComment;

      await orderProvider.createOrder(
        cart.items,
        cart.totalPrice,
        comment: fullComment,
        shopAddress: cart.selectedShopAddress,
      );

      if (!context.mounted) return;

      // Очищаем корзину
      cart.clear();

      // Переходим в меню заказов
      Navigator.of(context).pop(); // Закрываем корзину
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const OrdersPage(),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заказ успешно создан!'),
          backgroundColor: Color(0xFF004D40),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка создания заказа: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Диалог для ввода комментария с возможностью заказать
  void _showCommentDialogWithOrder(BuildContext context, CartProvider cart) {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text(
          'Комментарий к заказу',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Введите комментарий к заказу...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Две кнопки внизу диалога
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        final comment = controller.text.trim().isEmpty
                            ? null
                            : controller.text.trim();
                        _showPickupTimeDialog(context, cart, comment);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Заказать',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Просто закрываем диалог и возвращаемся к корзине
                        Navigator.of(dialogContext).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[600],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Вернуться к заказу',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

  /// Диалог для ввода комментария (старый метод, оставлен для совместимости)
  void _showCommentDialog(
    BuildContext context,
    String? initialComment,
    Function(String?) onSave,
  ) {
    final TextEditingController controller =
        TextEditingController(text: initialComment ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text('Комментарий к заказу'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Введите комментарий к заказу...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text.trim().isEmpty ? null : controller.text.trim());
              Navigator.of(dialogContext).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

