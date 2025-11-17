import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_menu_page.dart';
import 'registration_page.dart';
import 'cart_provider.dart';
import 'order_provider.dart';
import 'notification_service.dart';

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
            scaffoldBackgroundColor: Colors.white,
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
      final registered = prefs.getBool('is_registered') ?? false;
      
      setState(() {
        _isRegistered = registered;
        _isLoading = false;
      });

      if (registered && mounted) {
        // Пользователь зарегистрирован, переходим в приложение
        WidgetsBinding.instance.addPostFrameCallback((_) {
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
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
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
