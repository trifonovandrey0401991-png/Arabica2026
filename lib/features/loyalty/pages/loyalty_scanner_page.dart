import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/loyalty_service.dart';

class LoyaltyScannerPage extends StatefulWidget {
  const LoyaltyScannerPage({super.key});

  @override
  State<LoyaltyScannerPage> createState() => _LoyaltyScannerPageState();
}

class _LoyaltyScannerPageState extends State<LoyaltyScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  LoyaltyInfo? _client;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _lastQr;

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
    _lastQr = code;
    _processScan(code);
  }

  Future<void> _processScan(String qr) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final client = await LoyaltyService.addPoint(qr);
      if (mounted) {
        setState(() {
          _client = client;
        });
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка при обработке QR-кода';
        final errorString = e.toString().toLowerCase();
        
        if (errorString.contains('не найден') || 
            errorString.contains('not found') ||
            errorString.contains('клиент не найден')) {
          errorMessage = 'Клиент с таким QR-кодом не найден';
        } else if (errorString.contains('failed to fetch') || 
                   errorString.contains('connection') ||
                   errorString.contains('network')) {
          errorMessage = 'Ошибка подключения к серверу';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Превышено время ожидания';
        }
        
        setState(() {
          _errorMessage = errorMessage;
          _client = null;
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

  Future<void> _redeem() async {
    final qr = _client?.qr;
    if (qr == null) return;

    setState(() {
      _isProcessing = true;
    });
    try {
      final client = await LoyaltyService.redeem(qr);
      if (mounted) {
        setState(() {
          _client = client;
          _errorMessage = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Баллы списаны, напиток выдан!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка при списании баллов';
        final errorString = e.toString().toLowerCase();
        
        if (errorString.contains('failed to fetch') || 
            errorString.contains('connection') ||
            errorString.contains('network')) {
          errorMessage = 'Ошибка подключения к серверу';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Превышено время ожидания';
        } else if (errorString.contains('недостаточно') || 
                   errorString.contains('not enough')) {
          errorMessage = 'Недостаточно баллов для списания';
        }
        
        setState(() {
          _errorMessage = errorMessage;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _resetScan() {
    setState(() {
      _client = null;
      _lastQr = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Списать бонусы'),
        actions: [
          IconButton(
            icon: Icon(_controller.torchState.value == TorchState.on
                ? Icons.flashlight_off
                : Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: Icon(_controller.cameraFacingState.value == CameraFacing.back
                ? Icons.cameraswitch
                : Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          )
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(16),
              child: _buildDetails(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    if (_isProcessing && _client == null && _errorMessage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _resetScan,
            child: const Text('Сканировать снова'),
          ),
        ],
      );
    }

    final client = _client;
    if (client == null) {
      return const Center(
        child: Text(
          'Наведите камеру на QR-код клиента, чтобы начислить балл.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          client.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(client.phone),
        const SizedBox(height: 16),
        Card(
          color: Colors.teal.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Баллы: ${client.points}/10'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (client.points.clamp(0, 10)) / 10,
                  backgroundColor: Colors.grey.shade300,
                ),
                const SizedBox(height: 8),
                Text('Бесплатных напитков: ${client.freeDrinks}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (client.readyForRedeem)
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _redeem,
            icon: const Icon(Icons.card_giftcard),
            label: const Text('Списать баллы и выдать напиток'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
          )
        else
          ElevatedButton(
            onPressed: _resetScan,
            child: const Text('Сканировать следующий QR'),
          ),
      ],
    );
  }
}

extension on List<Barcode> {
  Barcode? get firstOrNull => isEmpty ? null : this[0];
}




