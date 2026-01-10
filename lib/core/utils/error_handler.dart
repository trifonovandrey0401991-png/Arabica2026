import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'logger.dart';

/// Типы ошибок приложения
enum AppErrorType {
  network,      // Ошибки сети (нет интернета, таймаут)
  server,       // Ошибки сервера (500, 502, etc.)
  validation,   // Ошибки валидации данных
  auth,         // Ошибки авторизации
  notFound,     // Ресурс не найден (404)
  unknown,      // Неизвестная ошибка
}

/// Модель ошибки приложения
class AppError {
  final AppErrorType type;
  final String message;
  final String? technicalDetails;
  final Object? originalError;
  final StackTrace? stackTrace;

  const AppError({
    required this.type,
    required this.message,
    this.technicalDetails,
    this.originalError,
    this.stackTrace,
  });

  /// Получить читаемое сообщение для пользователя
  String get userMessage {
    switch (type) {
      case AppErrorType.network:
        return 'Нет подключения к интернету. Проверьте соединение и попробуйте снова.';
      case AppErrorType.server:
        return 'Сервер временно недоступен. Попробуйте позже.';
      case AppErrorType.validation:
        return message;
      case AppErrorType.auth:
        return 'Ошибка авторизации. Пожалуйста, войдите заново.';
      case AppErrorType.notFound:
        return 'Запрашиваемые данные не найдены.';
      case AppErrorType.unknown:
        return 'Произошла непредвиденная ошибка. Попробуйте позже.';
    }
  }
}

/// Централизованный обработчик ошибок
class ErrorHandler {
  /// Обработать исключение и вернуть AppError
  static AppError handle(Object error, [StackTrace? stackTrace]) {
    Logger.error('ErrorHandler caught error', error, stackTrace);

    // Ошибки сети
    if (error is SocketException) {
      return AppError(
        type: AppErrorType.network,
        message: 'Ошибка сети',
        technicalDetails: error.message,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (error is TimeoutException) {
      return AppError(
        type: AppErrorType.network,
        message: 'Превышено время ожидания',
        technicalDetails: 'Timeout: ${error.duration}',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // HTTP ошибки (если передали как Exception с кодом в сообщении)
    final errorString = error.toString();

    if (errorString.contains('404')) {
      return AppError(
        type: AppErrorType.notFound,
        message: 'Не найдено',
        technicalDetails: errorString,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (errorString.contains('401') || errorString.contains('403')) {
      return AppError(
        type: AppErrorType.auth,
        message: 'Ошибка авторизации',
        technicalDetails: errorString,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return AppError(
        type: AppErrorType.server,
        message: 'Ошибка сервера',
        technicalDetails: errorString,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Неизвестная ошибка
    return AppError(
      type: AppErrorType.unknown,
      message: 'Неизвестная ошибка',
      technicalDetails: errorString,
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Показать SnackBar с ошибкой
  static void showError(BuildContext context, AppError error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.userMessage),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Показать SnackBar с ошибкой из Exception
  static void showException(BuildContext context, Object error, [StackTrace? stackTrace]) {
    final appError = handle(error, stackTrace);
    showError(context, appError);
  }

  /// Показать простое сообщение об ошибке
  static void showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Показать сообщение об успехе
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Показать предупреждение
  static void showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Обёртка для Future с автоматической обработкой ошибок
  static Future<T?> tryAsync<T>(
    Future<T> Function() action, {
    BuildContext? context,
    String? errorMessage,
    T? defaultValue,
  }) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      final appError = handle(e, stackTrace);

      if (context != null && context.mounted) {
        showError(context, AppError(
          type: appError.type,
          message: errorMessage ?? appError.message,
          technicalDetails: appError.technicalDetails,
          originalError: appError.originalError,
          stackTrace: appError.stackTrace,
        ));
      }

      return defaultValue;
    }
  }
}
