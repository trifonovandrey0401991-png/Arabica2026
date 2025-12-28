import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'core/utils/logger.dart';

/// Страница управления условиями акций для админа
class LoyaltyPromoManagementPage extends StatefulWidget {
  const LoyaltyPromoManagementPage({super.key});

  @override
  State<LoyaltyPromoManagementPage> createState() => _LoyaltyPromoManagementPageState();
}

class _LoyaltyPromoManagementPageState extends State<LoyaltyPromoManagementPage> {
  final TextEditingController _promoTextController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPromoText();
  }

  @override
  void dispose() {
    _promoTextController.dispose();
    super.dispose();
  }

  Future<void> _loadPromoText() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      const serverUrl = 'https://arabica26.ru';
      final uri = Uri.parse('$serverUrl/api/loyalty-promo');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final promoText = data['promoText'] ?? '';
          _promoTextController.text = promoText;
          Logger.debug('✅ Условия акций загружены: ${promoText.length} символов');
        } else {
          _error = data['error'] ?? 'Не удалось загрузить условия акций';
        }
      } else {
        _error = 'Ошибка сервера: ${response.statusCode}';
      }
    } catch (e) {
      Logger.error('Ошибка загрузки условий акций', e);
      _error = 'Ошибка загрузки: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePromoText() async {
    if (_promoTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите текст условий акции'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      const serverUrl = 'https://arabica26.ru';
      final uri = Uri.parse('$serverUrl/api/loyalty-promo');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'promoText': _promoTextController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Условия акций сохранены');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Условия акций успешно сохранены'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          _error = data['error'] ?? 'Не удалось сохранить условия акций';
        }
      } else {
        _error = 'Ошибка сервера: ${response.statusCode}';
      }
    } catch (e) {
      Logger.error('Ошибка сохранения условий акций', e);
      _error = 'Ошибка сохранения: ${e.toString()}';
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление условиями акций'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Условия акции',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Введите текст условий акции, который будет отображаться в карте лояльности для всех клиентов.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _promoTextController,
                            maxLines: 10,
                            decoration: const InputDecoration(
                              labelText: 'Текст условий акции',
                              hintText: 'Например: При покупке 10 напитков получите 1 бесплатный...',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _savePromoText,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(_isSaving ? 'Сохранение...' : 'Сохранить'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF004D40),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Предпросмотр',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _promoTextController.text.isEmpty
                                  ? 'Текст условий акции появится здесь...'
                                  : _promoTextController.text,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

