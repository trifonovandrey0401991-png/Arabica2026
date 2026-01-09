import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';
import '../services/fortune_wheel_service.dart';
import '../widgets/animated_wheel_widget.dart';

/// Страница Колеса Удачи
class FortuneWheelPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const FortuneWheelPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<FortuneWheelPage> createState() => _FortuneWheelPageState();
}

class _FortuneWheelPageState extends State<FortuneWheelPage> {
  List<FortuneWheelSector> _sectors = [];
  int _availableSpins = 0;
  bool _isLoading = true;
  bool _isSpinning = false;
  WheelSpinResult? _lastResult;
  final GlobalKey<AnimatedWheelWidgetState> _wheelKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final settings = await FortuneWheelService.getSettings();
    final spins = await FortuneWheelService.getAvailableSpins(widget.employeeId);

    if (mounted) {
      setState(() {
        _sectors = settings?.sectors ?? [];
        _availableSpins = spins.availableSpins;
        _isLoading = false;
      });
    }
  }

  Future<void> _spin() async {
    if (_isSpinning || _availableSpins <= 0) return;

    setState(() => _isSpinning = true);

    final result = await FortuneWheelService.spin(
      employeeId: widget.employeeId,
      employeeName: widget.employeeName,
    );

    if (result != null) {
      _wheelKey.currentState?.spinToSector(result.sector.index);
      _lastResult = result;
    } else {
      setState(() => _isSpinning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при прокрутке колеса'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSpinComplete() {
    setState(() {
      _isSpinning = false;
      _availableSpins = _lastResult?.remainingSpins ?? 0;
    });

    if (_lastResult != null) {
      _showResultDialog(_lastResult!);
    }
  }

  void _showResultDialog(WheelSpinResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🎉',
              style: TextStyle(fontSize: 60),
            ),
            const SizedBox(height: 16),
            const Text(
              'Поздравляем!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Вам выпало:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: result.sector.color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: result.sector.color, width: 2),
              ),
              child: Text(
                result.sector.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: result.sector.color,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Результат записан.\nАдминистратор свяжется с вами.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Колесо Удачи'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sectors.isEmpty
              ? _buildNoSectorsState()
              : _buildWheelContent(),
    );
  }

  Widget _buildNoSectorsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Колесо не настроено',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheelContent() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF004D40).withOpacity(0.1),
            Colors.white,
          ],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Заголовок
          const Text(
            '🎡 Испытай удачу!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _availableSpins > 0
                ? 'Осталось прокруток: $_availableSpins'
                : 'Прокрутки недоступны',
            style: TextStyle(
              fontSize: 16,
              color: _availableSpins > 0 ? Colors.green : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),

          // Колесо
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AnimatedWheelWidget(
                  key: _wheelKey,
                  sectors: _sectors,
                  isSpinning: _isSpinning,
                  onSpinComplete: _onSpinComplete,
                ),
              ),
            ),
          ),

          // Кнопка прокрутки
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _availableSpins > 0 && !_isSpinning ? _spin : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 4,
                ),
                child: _isSpinning
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Вращаем...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '🎲',
                            style: TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _availableSpins > 0 ? 'КРУТИТЬ!' : 'НЕТ ПРОКРУТОК',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _availableSpins > 0 ? Colors.white : Colors.grey[600],
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
