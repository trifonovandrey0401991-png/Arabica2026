import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_menu_page.dart';
import 'registration_page.dart';
import 'cart_provider.dart';
import 'order_provider.dart';
import 'notification_service.dart';
import 'loyalty_service.dart';
import 'loyalty_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const ArabicaApp());
}

class ArabicaApp extends StatelessWidget {
  const ArabicaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const MaterialColor primaryGreen = MaterialColor(0xFF004D40, {
      50: Color(0xFFE0F2F1),
      100: Color(0xFFB2DFDB),
      200: Color(0xFF80CBC4),
      300: Color(0xFF4DB6AC),
      400: Color(0xFF26A69A),
      500: Color(0xFF009688),
      600: Color(0xFF00897B),
      700: Color(0xFF00796B),
      800: Color(0xFF00695C),
      900: Color(0xFF004D40),
    });

    return CartProviderScope(
      child: OrderProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Arabica',
          theme: ThemeData(
            primarySwatch: primaryGreen,
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF004D40),
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
            ),
            scaffoldBackgroundColor: const Color(0xFF004D40), // Темно-бирюзовый фон
          ),
          routes: {
            '/home': (context) => Builder(
                  builder: (context) {
                    NotificationService.setGlobalContext(context);
                    return const MainMenuPage();
                  },
                ),
          },
          home: const _CheckRegistrationPage(),
        ),
      ),
    );
  }
}

/// Страница проверки регистрации
class _CheckRegistrationPage extends StatefulWidget {
  const _CheckRegistrationPage();

  @override
  State<_CheckRegistrationPage> createState() => _CheckRegistrationPageState();
}

class _CheckRegistrationPageState extends State<_CheckRegistrationPage> {
  bool _isLoading = true;
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhone = prefs.getString('user_phone');
      final savedName = prefs.getString('user_name');
      final isRegistered = prefs.getBool('is_registered') ?? false;
      
      // Сначала проверяем локальные данные (мгновенно)
      if (savedPhone != null && savedPhone.isNotEmpty && 
          savedName != null && savedName.isNotEmpty && isRegistered) {
        // Есть локальные данные - сразу показываем приветствие
        if (mounted) {
          setState(() {
            _isRegistered = true;
            _isLoading = false;
          });

          // Пользователь зарегистрирован, переходим в приложение
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => Builder(
                    builder: (context) {
                      NotificationService.setGlobalContext(context);
                      return const MainMenuPage();
                    },
                  ),
                ),
              );
            }
          });
        }
        
        // В фоне проверяем актуальность данных через API
        _verifyRegistrationInBackground(savedPhone);
        return;
      }
      
      // Если есть только телефон, проверяем через API
      if (savedPhone != null && savedPhone.isNotEmpty) {
        try {
          // Проверяем, существует ли пользователь в базе
          final loyaltyInfo = await LoyaltyService.fetchByPhone(savedPhone);
          
          // Пользователь найден в базе, обновляем данные
          await prefs.setBool('is_registered', true);
          await prefs.setString('user_name', loyaltyInfo.name);
          await prefs.setString('user_phone', loyaltyInfo.phone);
          await LoyaltyStorage.save(loyaltyInfo);
          
          if (mounted) {
            setState(() {
              _isRegistered = true;
              _isLoading = false;
            });

            // Пользователь зарегистрирован, переходим в приложение
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => Builder(
                      builder: (context) {
                        NotificationService.setGlobalContext(context);
                        return const MainMenuPage();
                      },
                    ),
                  ),
                );
              }
            });
          }
          return;
        } catch (e) {
          // Пользователь не найден в базе или сервер недоступен
          // Очищаем данные и показываем регистрацию
          // ignore: avoid_print
          print('⚠️ Пользователь не найден или сервер недоступен: $e');
          await prefs.remove('is_registered');
          await prefs.remove('user_name');
          await prefs.remove('user_phone');
        }
      }
      
      // Пользователь не зарегистрирован или не найден в базе
      if (mounted) {
        setState(() {
          _isRegistered = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('❌ Ошибка при проверке регистрации: $e');
      if (mounted) {
        setState(() {
          _isRegistered = false;
          _isLoading = false;
        });
      }
    }
  }

  /// Проверка регистрации в фоне (без блокировки UI)
  Future<void> _verifyRegistrationInBackground(String phone) async {
    try {
      final loyaltyInfo = await LoyaltyService.fetchByPhone(phone);
      final prefs = await SharedPreferences.getInstance();
      
      // Обновляем данные в фоне
      await prefs.setBool('is_registered', true);
      await prefs.setString('user_name', loyaltyInfo.name);
      await prefs.setString('user_phone', loyaltyInfo.phone);
      await LoyaltyStorage.save(loyaltyInfo);
    } catch (e) {
      // Игнорируем ошибки в фоновой проверке
      // ignore: avoid_print
      print('⚠️ Фоновая проверка регистрации не удалась: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF004D40),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    if (_isRegistered) {
      return Builder(
        builder: (context) {
          NotificationService.setGlobalContext(context);
          return const MainMenuPage();
        },
      );
    }

    return const RegistrationPage();
  }
}
