import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'app/pages/main_menu_page.dart';
import 'features/clients/pages/registration_page.dart';
import 'features/auth/services/auth_service.dart';
import 'features/auth/pages/pin_entry_page.dart';
import 'features/auth/pages/pin_setup_page.dart';
import 'shared/providers/cart_provider.dart';
import 'shared/providers/order_provider.dart';
import 'shared/dialogs/notification_required_dialog.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_gps_service.dart';
import 'features/loyalty/services/loyalty_service.dart';
import 'features/loyalty/services/loyalty_storage.dart';
import 'features/shifts/services/shift_sync_service.dart';
import 'core/services/firebase_wrapper.dart';
import 'features/employees/services/user_role_service.dart';
import 'core/utils/logger.dart';
import 'features/clients/services/registration_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/base_http_service.dart';

// Условный импорт Firebase (для веб используется заглушка)
import 'core/services/firebase_service.dart' if (dart.library.html) 'core/services/firebase_service_stub.dart';

/// Глобальный флаг - показывать ли диалог об уведомлениях при запуске
bool _shouldShowNotificationDialog = false;

/// Глобальный ключ навигатора для auto-logout при 401
final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Увеличиваем лимит TCP соединений к одному хосту (по умолчанию 6)
  // 6 заняты семафором API + нужны слоты для Image.network и прочего
  HttpOverrides.global = _AppHttpOverrides();
  
  // Инициализация Firebase (только для мобильных платформ)
  try {
    Logger.debug('🔵 Начало инициализации Firebase Core...');
    await FirebaseWrapper.initializeApp();
    Logger.success('Firebase Core инициализирован');
    
    // Проверяем готовность Firebase без задержки
    Logger.debug('🔵 Проверка готовности Firebase...');
    
    // Инициализация Firebase Messaging
    Logger.debug('🔵 Начало инициализации Firebase Messaging...');
    await FirebaseService.initialize();
    Logger.success('Firebase Messaging инициализирован');

    // Проверяем, разрешены ли уведомления
    final notificationsEnabled = await FirebaseService.areNotificationsEnabled();
    if (!notificationsEnabled) {
      Logger.warning('Уведомления отключены - будет показан диалог');
      _shouldShowNotificationDialog = true;
    }
  } catch (e) {
    // Firebase недоступен (веб-платформа или пакеты не установлены)
    Logger.warning('Firebase не доступен: $e');
    Logger.info('Push-уведомления будут работать только на мобильных устройствах');
    // Инициализируем заглушку для веб
    try {
      await FirebaseService.initialize();
    } catch (e2) {
      Logger.warning('Ошибка инициализации Firebase Service: $e2');
    }
  }
  
  await NotificationService.initialize();

  // Инициализация геозон для уведомлений "Я на работе"
  try {
    await BackgroundGpsService.initialize();
    await BackgroundGpsService.start();
    Logger.success('Geofence сервис запущен');
  } catch (e) {
    Logger.warning('Ошибка инициализации Geofence: $e');
  }

  // Загрузка session token из хранилища (для API запросов)
  try {
    await AuthService().initSessionToken();
  } catch (e) {
    Logger.warning('Ошибка загрузки session token: $e');
  }

  // Синхронизация отчетов пересменки в фоне (не блокирует запуск)
  Future.microtask(() {
    ShiftSyncService.syncAllReports().catchError((e) {
      Logger.warning('Ошибка синхронизации при запуске: $e');
    });
  });

  // Auto-logout при 401: очистка сессии + навигация на экран регистрации
  BaseHttpService.onUnauthorized = () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_registered');
    await prefs.remove('user_name');
    await prefs.remove('user_phone');
    await UserRoleService.clearUserRole();
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => RegistrationPage()),
      (_) => false,
    );
  };

  runApp(const ArabicaApp());
}

class ArabicaApp extends StatelessWidget {
  const ArabicaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final MaterialColor primaryGreen = MaterialColor(
      AppColors.primaryGreen.value,
      {
        50: AppColors.teal50,
        100: AppColors.teal100,
        200: AppColors.teal200,
        300: AppColors.teal300,
        400: AppColors.teal400,
        500: AppColors.teal500,
        600: AppColors.teal600,
        700: AppColors.teal700,
        800: AppColors.teal800,
        900: AppColors.primaryGreen,
      },
    );

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return CartProviderScope(
          child: OrderProviderScope(
            child: MaterialApp(
              navigatorKey: _navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Arabica',
              theme: ThemeData(
                primarySwatch: primaryGreen,
                appBarTheme: AppBarTheme(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  centerTitle: true,
                ),
                scaffoldBackgroundColor: AppColors.primaryGreen, // Темно-бирюзовый фон
              ),
              routes: {
                '/home': (context) => Builder(
                      builder: (context) {
                        NotificationService.setGlobalContext(context);
                        FirebaseService.setGlobalContext(context);
                        return const MainMenuPage();
                      },
                    ),
              },
              home: const _CheckRegistrationPage(),
            ),
          ),
        );
      },
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
  bool _needsPinEntry = false;
  bool _needsPinSetup = false;
  String? _userPhone;
  String? _userName;

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

        // Проверяем, есть ли у пользователя PIN-код
        Logger.debug('🔐 Проверяем наличие PIN-кода...');
        final authService = AuthService();
        final authStatus = await authService.getAuthStatus();
        Logger.debug('🔐 Auth status: $authStatus');
        final hasPin = authStatus['hasPin'] == true;

        if (hasPin) {
          // Есть PIN - показываем страницу ввода PIN
          Logger.info('✅ Пользователь имеет PIN-код, показываем страницу ввода');
          if (mounted) {
            setState(() {
              _isRegistered = true;
              _needsPinEntry = true;
              _isLoading = false;
            });
          }
          return;
        }

        // Нет PIN - показываем страницу создания PIN
        Logger.debug('⚠️ PIN не найден, показываем страницу создания PIN');
        if (mounted) {
          setState(() {
            _isRegistered = true;
            _needsPinSetup = true;
            _userPhone = savedPhone;
            _userName = savedName;
            _isLoading = false;
          });
        }
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

          // Сохраняем FCM токен (теперь когда phone известен)
          await FirebaseService.resaveToken();

          // Проверяем роль пользователя
          await _checkUserRole(loyaltyInfo.phone);
          
          // Сохраняем данные о клиенте на сервере (если это клиент)
          try {
            final roleData = await UserRoleService.getUserRole(loyaltyInfo.phone);
            if (roleData.role.name == 'client') {
              await RegistrationService.saveClientToServer(
                phone: loyaltyInfo.phone,
                name: loyaltyInfo.name,
                clientName: loyaltyInfo.name,
              );
              Logger.debug('✅ Данные клиента сохранены на сервере при проверке регистрации');
            }
          } catch (e) {
            Logger.warning('⚠️ Не удалось сохранить данные клиента на сервере: $e');
            // Продолжаем без сохранения на сервере
          }
          
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
                        FirebaseService.setGlobalContext(context);
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
          Logger.warning('Пользователь не найден или сервер недоступен: $e');
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
      Logger.error('Ошибка при проверке регистрации', e);
      if (mounted) {
        setState(() {
          _isRegistered = false;
          _isLoading = false;
        });
      }
    }
  }

  /// Проверка роли пользователя
  Future<void> _checkUserRole(String phone) async {
    try {
      Logger.debug('🔍 Проверка роли пользователя...');
      final roleData = await UserRoleService.getUserRole(phone);
      
      // Сохраняем роль
      await UserRoleService.saveUserRole(roleData);
      
      // Обновляем имя пользователя, если нужно
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', roleData.displayName);
      
      Logger.success('Роль пользователя определена: ${roleData.role.name}');
      Logger.info('Имя для отображения: ${roleData.displayName}');
    } catch (e) {
      Logger.warning('Ошибка проверки роли: $e');
      // Продолжаем работу без роли (по умолчанию клиент)
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _SplashScreen();
    }

    // Если нужно создать PIN-код (существующий пользователь без PIN)
    if (_needsPinSetup) {
      return PinSetupPage(
        phone: _userPhone ?? '',
        name: _userName ?? 'Пользователь',
        showLogout: true,
        onSuccess: () {
          // После создания PIN переходим в приложение
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => Builder(
                builder: (context) {
                  NotificationService.setGlobalContext(context);
                  FirebaseService.setGlobalContext(context);
                  return const MainMenuPage();
                },
              ),
            ),
          );
        },
      );
    }

    // Если нужен ввод PIN-кода (уже есть PIN)
    if (_needsPinEntry) {
      return PinEntryPage(
        onSuccess: () {
          // После успешного ввода PIN переходим в приложение
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => Builder(
                builder: (context) {
                  NotificationService.setGlobalContext(context);
                  FirebaseService.setGlobalContext(context);
                  return const MainMenuPage();
                },
              ),
            ),
          );
        },
      );
    }

    if (_isRegistered) {
      return Builder(
        builder: (context) {
          NotificationService.setGlobalContext(context);
          FirebaseService.setGlobalContext(context);

          // Показываем диалог об уведомлениях если нужно
          if (_shouldShowNotificationDialog) {
            _shouldShowNotificationDialog = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              NotificationRequiredDialog.show(context, showBackButton: false);
            });
          }

          // Проверка обновлений приложения (после загрузки UI)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppUpdateService.checkForUpdate(context);
          });

          return const MainMenuPage();
        },
      );
    }

    return const RegistrationPage();
  }
}

/// Экран загрузки с адаптивным логотипом
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    // Адаптивный размер логотипа - 50% от ширины экрана
    final screenWidth = MediaQuery.of(context).size.width;
    final logoSize = screenWidth * 0.5;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.emerald, // Основной тёмно-бирюзовый
              AppColors.deepEmerald, // Ещё темнее внизу
            ],
          ),
        ),
        child: Center(
          child: Image.asset(
            'assets/images/arabica_logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// Увеличенный лимит TCP соединений к одному хосту
class _AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.maxConnectionsPerHost = 12;
    return client;
  }
}
