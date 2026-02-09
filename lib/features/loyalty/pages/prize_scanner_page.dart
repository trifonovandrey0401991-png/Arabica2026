import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';

/// Страница сканирования QR-кода приза клиента (для сотрудников)
class PrizeScannerPage extends StatefulWidget {
  const PrizeScannerPage({super.key});

  @override
  State<PrizeScannerPage> createState() => _PrizeScannerPageState();
}

class _PrizeScannerPageState extends State<PrizeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  Map<String, dynamic>? _scannedPrize;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _lastQr;

  // Данные сотрудника
  String? _employeePhone;
  String? _employeeName;

  // Цвета
  static const _primaryColor = Color(0xFF1A4D4D);
  static const _successGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];
  static const _errorColor = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  Future<void> _loadEmployeeData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _employeePhone = prefs.getString('user_phone');
      _employeeName = prefs.getString('user_name') ?? 'Сотрудник';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final String? code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty || code == _lastQr) {
      return;
    }
    // Проверяем, что это QR-токен приза (начинается с qr_)
    if (!code.startsWith('qr_')) {
      setState(() {
        _errorMessage = 'Это не QR-код приза';
        _scannedPrize = null;
      });
      return;
    }
    _lastQr = code;
    _processScan(code);
  }

  Future<void> _processScan(String qrToken) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final result = await LoyaltyGamificationService.scanPrizeQr(qrToken);

      if (mounted) {
        if (result != null && result['success'] == true) {
          setState(() {
            _scannedPrize = result['prize'];
          });
        } else {
          setState(() {
            _errorMessage = result?['error'] ?? 'Ошибка при сканировании QR-кода';
            _scannedPrize = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка подключения к серверу';
          _scannedPrize = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _issuePrize() async {
    if (_scannedPrize == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final success = await LoyaltyGamificationService.issuePrize(
        prizeId: _scannedPrize!['id'],
        employeePhone: _employeePhone ?? '',
        employeeName: _employeeName ?? 'Сотрудник',
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.check_circle, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Приз выдан!',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: _successGradient[0],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
          _resetScanner();
        } else {
          setState(() {
            _errorMessage = 'Не удалось выдать приз';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка при выдаче приза';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _postponePrize() async {
    if (_scannedPrize == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final newQrToken = await LoyaltyGamificationService.postponePrize(
        _scannedPrize!['id'],
      );

      if (mounted) {
        if (newQrToken != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.schedule, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Приз отложен. Клиент получит новый QR.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
          _resetScanner();
        } else {
          setState(() {
            _errorMessage = 'Не удалось отложить приз';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка при отложении приза';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _resetScanner() {
    setState(() {
      _scannedPrize = null;
      _errorMessage = null;
      _lastQr = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF051515),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        title: const Text('Выдать приз'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Камера
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Затемнение сверху
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.25,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Text(
                    _scannedPrize != null
                        ? 'Приз отсканирован'
                        : 'Наведите на QR-код приза клиента',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Рамка сканирования
          if (_scannedPrize == null)
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),

          // Индикатор загрузки
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),

          // Карточка приза (после сканирования)
          if (_scannedPrize != null)
            _buildPrizeCard(),

          // Ошибка
          if (_errorMessage != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _errorColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          _lastQr = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrizeCard() {
    final prize = _scannedPrize!;
    final prizeModel = ClientPrize.fromJson(prize);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0D2E2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        prizeModel.prizeColor,
                        prizeModel.prizeColor.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: prizeModel.prizeColor.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    prizeModel.prizeIcon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Приз клиента',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),
                      Text(
                        prize['prize'] ?? '',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Информация о клиенте
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow('Клиент', prize['clientName'] ?? 'Клиент'),
                  const SizedBox(height: 8),
                  _infoRow('Телефон', _formatPhone(prize['clientPhone'] ?? '')),
                  const SizedBox(height: 8),
                  _infoRow('Дата выигрыша', _formatDate(prize['spinDate'])),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Кнопки
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _postponePrize,
                    icon: const Icon(Icons.schedule),
                    label: const Text('Отложить'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _issuePrize,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Выдать'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Кнопка отмены
            TextButton(
              onPressed: _resetScanner,
              child: Text(
                'Сканировать другой QR',
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatPhone(String phone) {
    if (phone.length == 11 && phone.startsWith('7')) {
      return '+${phone[0]} ${phone.substring(1, 4)} ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd.MM.yyyy HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }
}
