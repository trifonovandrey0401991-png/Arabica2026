import 'dart:async';
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
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/services/firebase_wrapper.dart';
import 'features/employees/services/user_role_service.dart';
import 'core/utils/logger.dart';
import 'features/clients/services/registration_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/base_http_service.dart';
import 'features/onboarding/pages/permission_onboarding_page.dart';

// Условный импорт Firebase (для веб используется заглушка)
import 'core/services/firebase_service.dart' if (dart.library.html) 'core/services/firebase_service_stub.dart';
import 'features/messenger/services/call_service.dart';
import 'features/messenger/services/messenger_ws_service.dart';
import 'features/messenger/pages/call_page.dart';
import 'features/messenger/widgets/call_overlay.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
/// Глобальный флаг - показывать ли диалог об уведомлениях при запуске
bool _shouldShowNotificationDialog = false;

/// Pending shared content from external apps (WhatsApp, Telegram, etc.)
class SharedContentHolder {
  static List<SharedMediaFile>? pendingFiles;
  static String? pendingText;
  static StreamSubscription? _mediaSub;
  static StreamSubscription? _textSub;

  static void initialize() {
    // Content shared while app is running
    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) pendingFiles = files;
    });

    // Content shared when app was closed (cold start)
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) pendingFiles = files;
    });
  }

  static bool get hasPending => pendingFiles != null || pendingText != null;

  static void clear() {
    pendingFiles = null;
    pendingText = null;
  }
}

/// Глобальный ключ навигатора — используется тот же экземпляр, что и в FirebaseService
/// (один ключ → один NavigatorState, нет рассинхронизации)
final GlobalKey<NavigatorState> navigatorKey = FirebaseService.navigatorKey;

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

    // Инициализация Crashlytics — перехват ошибок Flutter
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    Logger.success('Firebase Crashlytics инициализирован');

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
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => RegistrationPage()),
      (_) => false,
    );
  };

  // Listen for shared content from external apps
  SharedContentHolder.initialize();

  runApp(const ArabicaApp());
}

/// Глобальный слушатель входящих звонков — показывает CallPage автоматически.
/// Живёт на уровне MaterialApp, не теряется при навигации.
class _GlobalCallListener extends StatefulWidget {
  final Widget child;
  const _GlobalCallListener({super.key, required this.child});

  @override
  State<_GlobalCallListener> createState() => _GlobalCallListenerState();
}

class _GlobalCallListenerState extends State<_GlobalCallListener> {
  StreamSubscription<CallState>? _sub;
  bool _callPageOpen = false;

  @override
  void initState() {
    super.initState();
    _sub = CallService.instance.onStateChanged.listen((state) {
      if (state == CallState.incoming && !_callPageOpen) {
        _openCallPage();
      }
      if (state == CallState.idle || state == CallState.ended) {
        _callPageOpen = false;
      }
    });
  }

  void _openCallPage() {
    final call = CallService.instance.currentCall;
    final nav = navigatorKey.currentState;
    if (call == null || nav == null) return;
    _callPageOpen = true;
    nav.push(
      MaterialPageRoute(builder: (_) => CallPage(callInfo: call)),
    ).then((_) => _callPageOpen = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Arabica',
              builder: (context, child) {
                return _GlobalCallListener(
                  child: Stack(
                    children: [
                      child ?? const SizedBox.shrink(),
                      const CallOverlayBar(),
                    ],
                  ),
                );
              },
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
                        return PermissionOnboardingPage(
                          onComplete: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (ctx) {
                                  NotificationService.setGlobalContext(ctx);
                                  FirebaseService.setGlobalContext(ctx);
                                  return const MainMenuPage();
                                },
                              ),
                            );
                          },
                        );
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

        // FAST PATH: check for pending incoming call BEFORE any API calls.
        // This saves 1-2 seconds by skipping getAuthStatus() network request.
        final pendingCall = prefs.getString('pending_incoming_call');
        final pendingCallTime = prefs.getInt('pending_incoming_call_time') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final isRecentCall = pendingCall != null && (now - pendingCallTime) < 60000;

        if (isRecentCall) {
          Logger.info('📞 Recent pending call found — fast path, skipping PIN');
          MessengerWsService.instance.connect(savedPhone);
          CallService.instance.init(savedPhone, savedName);
          await prefs.setBool('pending_call_accepted', true);
          if (mounted) {
            setState(() {
              _isRegistered = true;
              _isLoading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _navigateToApp();
            });
          }
          return;
        }

        // Инициализируем голосовые звонки + WebSocket мессенджера (для приёма звонков)
        MessengerWsService.instance.connect(savedPhone);
        CallService.instance.init(savedPhone, savedName);

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
          MessengerWsService.instance.connect(loyaltyInfo.phone);
          CallService.instance.init(loyaltyInfo.phone, loyaltyInfo.name);

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
                _navigateToApp();
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

  /// Navigate to app through permission onboarding
  void _navigateToApp() async {
    // Ensure call service is initialized after successful login
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final name = prefs.getString('user_name') ?? '';
    if (phone.isNotEmpty) {
      MessengerWsService.instance.connect(phone);
      CallService.instance.init(phone, name);
      // Always refresh role on app entry (fixes stale cached roles)
      await _checkUserRole(phone);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => Builder(
          builder: (context) {
            NotificationService.setGlobalContext(context);
            FirebaseService.setGlobalContext(context);
            return PermissionOnboardingPage(
              onComplete: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (ctx) {
                      NotificationService.setGlobalContext(ctx);
                      FirebaseService.setGlobalContext(ctx);
                      return const MainMenuPage();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
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
          _navigateToApp();
        },
      );
    }

    // Если нужен ввод PIN-кода (уже есть PIN)
    if (_needsPinEntry) {
      return PinEntryPage(
        onSuccess: () {
          // После успешного ввода PIN переходим в приложение
          _navigateToApp();
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

          return PermissionOnboardingPage(
            onComplete: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (ctx) {
                    NotificationService.setGlobalContext(ctx);
                    FirebaseService.setGlobalContext(ctx);
                    return const MainMenuPage();
                  },
                ),
              );
            },
          );
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
