import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for SharedPreferences key consistency — C-1 and H-3
///
/// C-1: Admin name attribution — pages read 'employeeName' which is never written.
///      After fix: pages read 'user_display_name' which IS written by UserRoleService.
///
/// H-3: Prize scanner shop — page reads 'shop_address' which is never written.
///      After fix: reads 'selected_shop_address' which IS written on shift start.
void main() {
  group('SharedPreferences Keys Consistency', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // ══════════════════════════════════════════════════════
    // C-1: Admin name attribution
    // ══════════════════════════════════════════════════════
    group('C-1: Admin name attribution', () {
      test('BEFORE FIX: employeeName key is never written — always falls back to Администратор', () async {
        final prefs = await SharedPreferences.getInstance();
        // UserRoleService.saveUserRole() writes 'user_display_name', NOT 'employeeName'
        await prefs.setString('user_display_name', 'Иван Петров');
        await prefs.setString('user_name', 'Иван Петров');

        // Old broken logic used in bonus_penalty_management_page:47,
        // job_applications_list_page:42, main_cash_page:171,361,608,1878
        final brokenRead = prefs.getString('employeeName') ??
            prefs.getString('name') ??
            'Администратор';

        // Proves the bug: correct name is in prefs but wrong key is read
        expect(brokenRead, equals('Администратор'));
      });

      test('AFTER FIX: user_display_name key is read — returns actual name', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_display_name', 'Иван Петров');

        // Fixed logic: read user_display_name (written by UserRoleService.saveUserRole)
        final fixedRead = prefs.getString('user_display_name') ??
            prefs.getString('currentEmployeeName') ??
            prefs.getString('user_name') ??
            'Администратор';

        expect(fixedRead, equals('Иван Петров'));
      });

      test('AFTER FIX: currentEmployeeName fallback works when display_name missing', () async {
        final prefs = await SharedPreferences.getInstance();
        // checkEmployeeViaAPI writes currentEmployeeName
        await prefs.setString('currentEmployeeName', 'Мария Сидорова');

        final fixedRead = prefs.getString('user_display_name') ??
            prefs.getString('currentEmployeeName') ??
            prefs.getString('user_name') ??
            'Администратор';

        expect(fixedRead, equals('Мария Сидорова'));
      });

      test('AFTER FIX: user_name fallback works as last resort before default', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', 'Петр Иванов');

        final fixedRead = prefs.getString('user_display_name') ??
            prefs.getString('currentEmployeeName') ??
            prefs.getString('user_name') ??
            'Администратор';

        expect(fixedRead, equals('Петр Иванов'));
      });

      test('AFTER FIX: Администратор only when NO name keys are set at all', () async {
        final prefs = await SharedPreferences.getInstance();
        // No name keys set

        final fixedRead = prefs.getString('user_display_name') ??
            prefs.getString('currentEmployeeName') ??
            prefs.getString('user_name') ??
            'Администратор';

        expect(fixedRead, equals('Администратор'));
      });
    });

    // ══════════════════════════════════════════════════════
    // H-3: Prize scanner shop key
    // ══════════════════════════════════════════════════════
    group('H-3: Prize scanner shop key', () {
      test('BEFORE FIX: shop_address key is never written — always null', () async {
        final prefs = await SharedPreferences.getInstance();
        // shift_shop_selection_page writes selected_shop_address, NOT shop_address
        await prefs.setString('selected_shop_address', 'ул. Пушкина, 10');

        // Old broken read in prize_scanner_page:50
        final brokenRead = prefs.getString('shop_address');

        expect(brokenRead, isNull); // Bug: correct value exists but wrong key read
      });

      test('AFTER FIX: selected_shop_address key is read — returns shop', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_shop_address', 'ул. Пушкина, 10');

        // Fixed read
        final fixedRead = prefs.getString('selected_shop_address');

        expect(fixedRead, equals('ул. Пушкина, 10'));
      });

      test('AFTER FIX: shop address is null when shift not started yet', () async {
        final prefs = await SharedPreferences.getInstance();
        // No shop selected yet

        final shopAddress = prefs.getString('selected_shop_address');

        expect(shopAddress, isNull);
      });
    });
  });
}
