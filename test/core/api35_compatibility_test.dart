/// Tests to verify Android API 35 compatibility.
/// Run BEFORE and AFTER changing targetSdkVersion from 34 to 35.
///
/// Checks:
/// 1. Push notification service initialization
/// 2. Background GPS service configuration
/// 3. Firebase service setup
/// 4. Notification channels
/// 5. Permission declarations in manifest
/// 6. Network security config
library;

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('API 35 Compatibility — AndroidManifest permissions', () {
    late String manifestContent;

    setUpAll(() {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue,
          reason: 'AndroidManifest.xml must exist');
      manifestContent = manifestFile.readAsStringSync();
    });

    test('POST_NOTIFICATIONS permission declared (required API 33+)', () {
      expect(manifestContent, contains('android.permission.POST_NOTIFICATIONS'),
          reason: 'POST_NOTIFICATIONS required for push on API 33+');
    });

    test('ACCESS_FINE_LOCATION permission declared', () {
      expect(manifestContent, contains('android.permission.ACCESS_FINE_LOCATION'),
          reason: 'Required for GPS tracking');
    });

    test('ACCESS_BACKGROUND_LOCATION permission declared', () {
      expect(
          manifestContent, contains('android.permission.ACCESS_BACKGROUND_LOCATION'),
          reason: 'Required for background GPS on API 29+');
    });

    test('CAMERA permission declared', () {
      expect(manifestContent, contains('android.permission.CAMERA'),
          reason: 'Required for photo capture');
    });

    test('INTERNET permission declared', () {
      expect(manifestContent, contains('android.permission.INTERNET'),
          reason: 'Required for network requests');
    });

    test('enableOnBackInvokedCallback is true (predictive back gesture API 34+)',
        () {
      expect(manifestContent, contains('android:enableOnBackInvokedCallback="true"'),
          reason: 'Required for predictive back gesture on API 34+');
    });

    test('Camera feature is NOT required (graceful degradation)', () {
      expect(manifestContent, contains('android:required="false"'),
          reason: 'Camera should not be required to allow install on all devices');
    });
  });

  group('API 35 Compatibility — Build configuration', () {
    test('app/build.gradle exists', () {
      final buildGradle = File('android/app/build.gradle');
      expect(buildGradle.existsSync(), isTrue);
    });

    test('compileSdk >= 35', () {
      final buildGradle = File('android/app/build.gradle');
      final content = buildGradle.readAsStringSync();
      final match = RegExp(r'compileSdk\s*=\s*(\d+)').firstMatch(content);
      expect(match, isNotNull, reason: 'compileSdk must be defined');
      final version = int.parse(match!.group(1)!);
      expect(version, greaterThanOrEqualTo(35),
          reason: 'compileSdk must be >= 35 for API 35 target');
    });

    test('minSdk is reasonable (21-23)', () {
      final buildGradle = File('android/app/build.gradle');
      final content = buildGradle.readAsStringSync();
      final match = RegExp(r'minSdk\s*=\s*(\d+)').firstMatch(content);
      expect(match, isNotNull, reason: 'minSdk must be defined');
      final version = int.parse(match!.group(1)!);
      expect(version, greaterThanOrEqualTo(21));
      expect(version, lessThanOrEqualTo(24));
    });

    test('ProGuard rules exist for release', () {
      final proguard = File('android/app/proguard-rules.pro');
      expect(proguard.existsSync(), isTrue,
          reason: 'ProGuard rules required for minifyEnabled=true');
      final content = proguard.readAsStringSync();
      expect(content, contains('firebase'),
          reason: 'Firebase classes must be kept');
      expect(content, contains('flutter'),
          reason: 'Flutter classes must be kept');
    });
  });

  group('API 35 Compatibility — Network security', () {
    test('network_security_config.xml exists', () {
      final config =
          File('android/app/src/main/res/xml/network_security_config.xml');
      expect(config.existsSync(), isTrue,
          reason: 'Network security config required for API 28+');
    });

    test('HTTPS enforced for production', () {
      final config =
          File('android/app/src/main/res/xml/network_security_config.xml');
      final content = config.readAsStringSync();
      expect(content, contains('arabica26.ru'),
          reason: 'Production domain must be configured');
      expect(content, contains('cleartextTrafficPermitted="false"'),
          reason: 'HTTPS must be enforced');
    });
  });

  group('API 35 Compatibility — Firebase configuration', () {
    test('google-services.json exists', () {
      final gsJson = File('android/app/google-services.json');
      expect(gsJson.existsSync(), isTrue,
          reason: 'Firebase config required for push notifications');
    });

    test('Firebase messaging default icon configured in manifest', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      final content = manifest.readAsStringSync();
      expect(content,
          contains('com.google.firebase.messaging.default_notification_icon'),
          reason: 'Default notification icon must be set for FCM');
    });
  });

  group('API 35 Compatibility — Background services', () {
    test('BackgroundGpsService uses WorkManager (not AlarmManager)', () {
      final service = File('lib/core/services/background_gps_service.dart');
      expect(service.existsSync(), isTrue);
      final content = service.readAsStringSync();
      expect(content, contains('Workmanager'),
          reason: 'Must use WorkManager for API 35 background tasks');
      expect(content, isNot(contains('AlarmManager')),
          reason: 'AlarmManager is restricted on API 35');
    });

    test('BackgroundGpsService has @pragma vm:entry-point', () {
      final service = File('lib/core/services/background_gps_service.dart');
      final content = service.readAsStringSync();
      expect(content, contains("@pragma('vm:entry-point')"),
          reason: 'Required for background callback on API 31+');
    });

    test('FirebaseService has background message handler with @pragma', () {
      final service = File('lib/core/services/firebase_service.dart');
      expect(service.existsSync(), isTrue);
      final content = service.readAsStringSync();
      expect(content, contains("@pragma('vm:entry-point')"),
          reason: 'Required for FCM background handler');
      expect(content, contains('onBackgroundMessage'),
          reason: 'Must register background message handler');
    });
  });

  group('API 35 Compatibility — Notification channels', () {
    test('FirebaseService uses flutter_local_notifications for channels', () {
      final service = File('lib/core/services/firebase_service.dart');
      final content = service.readAsStringSync();
      // API 26+ requires notification channels — created via flutter_local_notifications
      expect(content, contains('flutter_local_notifications'),
          reason: 'Notification channels required for API 26+');
    });

    test('NotificationService uses proper channel config', () {
      final service = File('lib/core/services/notification_service.dart');
      expect(service.existsSync(), isTrue);
      final content = service.readAsStringSync();
      expect(content, contains('AndroidNotificationDetails'),
          reason: 'Must use Android notification details with channel');
    });
  });

  group('API 35 Compatibility — targetSdk value', () {
    test('targetSdk is set to 35 (not flutter default 34)', () {
      final buildGradle = File('android/app/build.gradle');
      final content = buildGradle.readAsStringSync();
      // Should be hardcoded 35, not flutter.targetSdkVersion (which is 34)
      final hasHardcoded = content.contains('targetSdk = 35');
      final hasFlutterDefault =
          content.contains('targetSdk = flutter.targetSdkVersion');

      if (hasFlutterDefault && !hasHardcoded) {
        fail('targetSdk uses flutter.targetSdkVersion which defaults to 34. '
            'Must be hardcoded to 35 for Google Play.');
      }
      expect(hasHardcoded, isTrue,
          reason: 'targetSdk must be explicitly 35');
    });
  });
}
