// Shared Report List Widgets Tests
// Covers: ReportTabButton, formatDayGenitive, getWeekStart, groupReportsByDate

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:arabica_app/shared/widgets/report_list_widgets.dart';

/// Helper: wraps a widget in MaterialApp + ScreenUtilInit for testing.
Widget buildTestWidget(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    builder: (context, _) {
      return MaterialApp(
        home: Scaffold(
          body: Row(
            // Row needed because ReportTabButton uses Expanded
            children: [child],
          ),
        ),
      );
    },
  );
}

void main() {
  // ═══════════════════════════════════════════════════
  // 1. ReportTabButton widget tests
  // ═══════════════════════════════════════════════════
  group('ReportTabButton', () {
    testWidgets('renders label and count', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Pending',
          count: 42,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('shows icon when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Tab',
          count: 1,
          icon: Icons.check,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('hides icon when not provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Tab',
          count: 1,
        ),
      ));
      await tester.pumpAndSettle();

      // No Icon widget should be present at all
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('shows badge when badge > 0', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Tab',
          count: 5,
          badge: 3,
        ),
      ));
      await tester.pumpAndSettle();

      // Badge text "3" should appear separately from count "5"
      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('hides badge when badge is 0', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Tab',
          count: 5,
          badge: 0,
        ),
      ));
      await tester.pumpAndSettle();

      // Count "5" is present, but no badge text
      expect(find.text('5'), findsOneWidget);
      // Badge circle uses red color — ensure no red circle container
      final redContainers = tester.widgetList<Container>(
        find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final dec = widget.decoration as BoxDecoration;
            return dec.color == Colors.red && dec.shape == BoxShape.circle;
          }
          return false;
        }),
      );
      expect(redContainers.isEmpty, isTrue);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () => tapped = true,
          label: 'Tap Me',
          count: 0,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('selected state uses bold font weight', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: true,
          onTap: () {},
          label: 'Selected',
          count: 1,
        ),
      ));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Selected'));
      expect(textWidget.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('unselected state uses normal font weight', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Normal',
          count: 1,
        ),
      ));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Normal'));
      expect(textWidget.style?.fontWeight, FontWeight.normal);
    });

    testWidgets('selected state uses white text color', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: true,
          onTap: () {},
          label: 'White',
          count: 1,
        ),
      ));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('White'));
      expect(textWidget.style?.color, Colors.white);
    });

    testWidgets('unselected state uses dimmed text color', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Dim',
          count: 1,
        ),
      ));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Dim'));
      expect(textWidget.style?.color, Colors.white.withOpacity(0.5));
    });

    testWidgets('selected state has gradient decoration', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: true,
          onTap: () {},
          label: 'Grad',
          count: 1,
          accentColor: Colors.blue,
        ),
      ));
      await tester.pumpAndSettle();

      // Find the outer Container with BoxDecoration that has a gradient
      final containers = tester.widgetList<Container>(
        find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final dec = widget.decoration as BoxDecoration;
            return dec.gradient is LinearGradient;
          }
          return false;
        }),
      );
      expect(containers.isNotEmpty, isTrue);
    });

    testWidgets('unselected state has no gradient', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'NoGrad',
          count: 1,
          accentColor: Colors.blue,
        ),
      ));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<Container>(
        find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final dec = widget.decoration as BoxDecoration;
            return dec.gradient is LinearGradient;
          }
          return false;
        }),
      );
      expect(containers.isEmpty, isTrue);
    });

    testWidgets('selected border width is 2', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: true,
          onTap: () {},
          label: 'Border',
          count: 0,
          accentColor: Colors.teal,
        ),
      ));
      await tester.pumpAndSettle();

      final container = tester.widgetList<Container>(
        find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final dec = widget.decoration as BoxDecoration;
            return dec.border != null && dec.gradient is LinearGradient;
          }
          return false;
        }),
      ).first;
      final dec = container.decoration as BoxDecoration;
      final border = dec.border as Border;
      expect(border.top.width, 2);
    });

    testWidgets('unselected border width is 1', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ReportTabButton(
          isSelected: false,
          onTap: () {},
          label: 'Border',
          count: 0,
          accentColor: Colors.teal,
        ),
      ));
      await tester.pumpAndSettle();

      // Find the container that has a border but no gradient (unselected)
      final container = tester.widgetList<Container>(
        find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final dec = widget.decoration as BoxDecoration;
            return dec.border != null && dec.gradient == null;
          }
          return false;
        }),
      ).first;
      final dec = container.decoration as BoxDecoration;
      final border = dec.border as Border;
      expect(border.top.width, 1);
    });
  });

  // ═══════════════════════════════════════════════════
  // 2. formatDayGenitive tests
  // ═══════════════════════════════════════════════════
  group('formatDayGenitive', () {
    test('returns "1 января" for January 1', () {
      expect(formatDayGenitive(DateTime(2026, 1, 1)), '1 января');
    });

    test('returns "31 декабря" for December 31', () {
      expect(formatDayGenitive(DateTime(2026, 12, 31)), '31 декабря');
    });

    test('returns "14 февраля" for February 14', () {
      expect(formatDayGenitive(DateTime(2026, 2, 14)), '14 февраля');
    });

    test('returns "8 марта" for March 8', () {
      expect(formatDayGenitive(DateTime(2026, 3, 8)), '8 марта');
    });

    test('returns "23 мая" for May 23', () {
      expect(formatDayGenitive(DateTime(2026, 5, 23)), '23 мая');
    });

    test('returns "15 июля" for July 15', () {
      expect(formatDayGenitive(DateTime(2026, 7, 15)), '15 июля');
    });

    test('returns "30 сентября" for September 30', () {
      expect(formatDayGenitive(DateTime(2026, 9, 30)), '30 сентября');
    });

    test('returns "11 ноября" for November 11', () {
      expect(formatDayGenitive(DateTime(2026, 11, 11)), '11 ноября');
    });
  });

  // ═══════════════════════════════════════════════════
  // 3. getWeekStart tests
  // ═══════════════════════════════════════════════════
  group('getWeekStart', () {
    test('Monday returns the same date', () {
      // 2026-02-23 is Monday
      final monday = DateTime(2026, 2, 23);
      expect(monday.weekday, DateTime.monday);
      final result = getWeekStart(monday);
      expect(result, DateTime(2026, 2, 23));
    });

    test('Sunday returns the previous Monday', () {
      // 2026-03-01 is Sunday
      final sunday = DateTime(2026, 3, 1);
      expect(sunday.weekday, DateTime.sunday);
      final result = getWeekStart(sunday);
      expect(result, DateTime(2026, 2, 23)); // Previous Monday
    });

    test('Wednesday returns Monday of that week', () {
      // 2026-02-25 is Wednesday
      final wednesday = DateTime(2026, 2, 25);
      expect(wednesday.weekday, DateTime.wednesday);
      final result = getWeekStart(wednesday);
      expect(result, DateTime(2026, 2, 23)); // Monday
    });

    test('Tuesday returns Monday of that week', () {
      final tuesday = DateTime(2026, 2, 24);
      expect(tuesday.weekday, DateTime.tuesday);
      final result = getWeekStart(tuesday);
      expect(result, DateTime(2026, 2, 23));
    });

    test('Saturday returns Monday of that week', () {
      final saturday = DateTime(2026, 2, 28);
      expect(saturday.weekday, DateTime.saturday);
      final result = getWeekStart(saturday);
      expect(result, DateTime(2026, 2, 23));
    });

    test('Friday returns Monday of that week', () {
      final friday = DateTime(2026, 2, 27);
      expect(friday.weekday, DateTime.friday);
      final result = getWeekStart(friday);
      expect(result, DateTime(2026, 2, 23));
    });

    test('works across month boundary', () {
      // 2026-03-01 is Sunday, Monday is Feb 23
      final result = getWeekStart(DateTime(2026, 3, 1));
      expect(result, DateTime(2026, 2, 23));
    });

    test('works across year boundary', () {
      // 2026-01-01 is Thursday, Monday is Dec 29 2025
      final jan1 = DateTime(2026, 1, 1);
      expect(jan1.weekday, DateTime.thursday);
      final result = getWeekStart(jan1);
      expect(result, DateTime(2025, 12, 29));
    });
  });

  // ═══════════════════════════════════════════════════
  // 4. groupReportsByDate tests
  // ═══════════════════════════════════════════════════
  group('groupReportsByDate', () {
    // Helper: a simple report with a date
    DateTime Function(_TestReport) getDate = (r) => r.date;

    test('empty list returns empty groups', () {
      final groups = groupReportsByDate<_TestReport>([], getDate);
      expect(groups, isEmpty);
    });

    test('today\'s reports grouped as "Сегодня"', () {
      final now = DateTime.now();
      final reports = [
        _TestReport('r1', now),
        _TestReport('r2', now.subtract(Duration(hours: 3))),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 1);
      expect(groups[0].type, ReportGroupType.today);
      expect(groups[0].title, 'Сегодня');
      expect(groups[0].reports.length, 2);
    });

    test('yesterday\'s reports grouped as "Вчера"', () {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 1));
      final reports = [
        _TestReport('r1', yesterday),
        _TestReport('r2', yesterday.add(Duration(hours: 10))),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 1);
      expect(groups[0].type, ReportGroupType.yesterday);
      expect(groups[0].title, 'Вчера');
      expect(groups[0].reports.length, 2);
    });

    test('reports from 3 days ago grouped by day name', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final threeDaysAgo = today.subtract(Duration(days: 3));
      final reports = [
        _TestReport('r1', threeDaysAgo),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 1);
      expect(groups[0].type, ReportGroupType.day);
      expect(groups[0].title, formatDayGenitive(threeDaysAgo));
      expect(groups[0].reports.length, 1);
    });

    test('reports from 2 weeks ago grouped by week', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final twoWeeksAgo = today.subtract(Duration(days: 14));
      final reports = [
        _TestReport('r1', twoWeeksAgo),
        _TestReport('r2', twoWeeksAgo.add(Duration(days: 1))),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 1);
      expect(groups[0].type, ReportGroupType.week);
      expect(groups[0].title, startsWith('Неделя'));
      expect(groups[0].reports.length, 2);
    });

    test('reports from 2 months ago grouped by month', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final twoMonthsAgo = today.subtract(Duration(days: 60));
      final reports = [
        _TestReport('r1', twoMonthsAgo),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 1);
      expect(groups[0].type, ReportGroupType.month);
      final expectedMonth = monthNamesNominative[twoMonthsAgo.month];
      final expectedYear = twoMonthsAgo.year;
      expect(groups[0].title, '$expectedMonth $expectedYear');
      expect(groups[0].reports.length, 1);
    });

    test('mixed dates produce groups in correct order', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(Duration(days: 1));
      final threeDaysAgo = today.subtract(Duration(days: 3));
      final twoWeeksAgo = today.subtract(Duration(days: 14));
      final twoMonthsAgo = today.subtract(Duration(days: 60));

      final reports = [
        _TestReport('today1', today),
        _TestReport('yesterday1', yesterday),
        _TestReport('day1', threeDaysAgo),
        _TestReport('week1', twoWeeksAgo),
        _TestReport('month1', twoMonthsAgo),
      ];

      final groups = groupReportsByDate(reports, getDate);

      // Should have 5 groups: today, yesterday, day, week, month
      expect(groups.length, 5);
      expect(groups[0].type, ReportGroupType.today);
      expect(groups[1].type, ReportGroupType.yesterday);
      expect(groups[2].type, ReportGroupType.day);
      expect(groups[3].type, ReportGroupType.week);
      expect(groups[4].type, ReportGroupType.month);
    });

    test('multiple reports on same day go into same group', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final reports = [
        _TestReport('r1', today.add(Duration(hours: 1))),
        _TestReport('r2', today.add(Duration(hours: 5))),
        _TestReport('r3', today.add(Duration(hours: 10))),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 1);
      expect(groups[0].type, ReportGroupType.today);
      expect(groups[0].reports.length, 3);
    });

    test('reports from different days within the week get separate day groups',
        () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final threeDaysAgo = today.subtract(Duration(days: 3));
      final fourDaysAgo = today.subtract(Duration(days: 4));

      final reports = [
        _TestReport('r1', threeDaysAgo),
        _TestReport('r2', fourDaysAgo),
      ];

      final groups = groupReportsByDate(reports, getDate);

      expect(groups.length, 2);
      expect(groups[0].type, ReportGroupType.day);
      expect(groups[1].type, ReportGroupType.day);
      expect(groups[0].title, isNot(groups[1].title));
    });

    test('reports from same week (>7 days ago) grouped together', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 10 and 12 days ago are in the same week if close enough
      final tenDaysAgo = today.subtract(Duration(days: 10));
      final twelveDaysAgo = today.subtract(Duration(days: 12));

      // Both should be in the same week if they share the same Monday
      final weekStart10 = getWeekStart(tenDaysAgo);
      final weekStart12 = getWeekStart(twelveDaysAgo);

      final reports = [
        _TestReport('r1', tenDaysAgo),
        _TestReport('r2', twelveDaysAgo),
      ];

      final groups = groupReportsByDate(reports, getDate);

      if (weekStart10 == weekStart12) {
        // Same week — one group
        expect(groups.length, 1);
        expect(groups[0].type, ReportGroupType.week);
        expect(groups[0].reports.length, 2);
      } else {
        // Different weeks — two groups
        expect(groups.length, 2);
        expect(groups[0].type, ReportGroupType.week);
        expect(groups[1].type, ReportGroupType.week);
      }
    });
  });

  // ═══════════════════════════════════════════════════
  // 5. ReportGroup class tests
  // ═══════════════════════════════════════════════════
  group('ReportGroup', () {
    test('stores type, title, reports, and optional date', () {
      final reports = ['a', 'b', 'c'];
      final date = DateTime(2026, 2, 28);
      final group = ReportGroup<String>(
        type: ReportGroupType.today,
        title: 'Сегодня',
        reports: reports,
        date: date,
      );

      expect(group.type, ReportGroupType.today);
      expect(group.title, 'Сегодня');
      expect(group.reports, reports);
      expect(group.date, date);
    });

    test('date defaults to null', () {
      final group = ReportGroup<String>(
        type: ReportGroupType.month,
        title: 'Январь 2026',
        reports: ['x'],
      );

      expect(group.date, isNull);
    });
  });

  // ═══════════════════════════════════════════════════
  // 6. ReportGroupType enum tests
  // ═══════════════════════════════════════════════════
  group('ReportGroupType', () {
    test('has all expected values', () {
      expect(ReportGroupType.values, containsAll([
        ReportGroupType.today,
        ReportGroupType.yesterday,
        ReportGroupType.day,
        ReportGroupType.week,
        ReportGroupType.month,
      ]));
      expect(ReportGroupType.values.length, 5);
    });
  });

  // ═══════════════════════════════════════════════════
  // 7. getGroupIcon / getGroupColor tests
  // ═══════════════════════════════════════════════════
  group('getGroupIcon', () {
    test('returns Icons.today for today', () {
      expect(getGroupIcon(ReportGroupType.today), Icons.today);
    });

    test('returns Icons.history for yesterday', () {
      expect(getGroupIcon(ReportGroupType.yesterday), Icons.history);
    });

    test('returns Icons.calendar_today for day', () {
      expect(getGroupIcon(ReportGroupType.day), Icons.calendar_today);
    });

    test('returns Icons.date_range for week', () {
      expect(getGroupIcon(ReportGroupType.week), Icons.date_range);
    });

    test('returns Icons.calendar_month for month', () {
      expect(getGroupIcon(ReportGroupType.month), Icons.calendar_month);
    });
  });

  group('getGroupColor', () {
    test('returns green for today', () {
      expect(getGroupColor(ReportGroupType.today), Colors.green);
    });

    test('returns blue for yesterday', () {
      expect(getGroupColor(ReportGroupType.yesterday), Colors.blue);
    });

    test('returns cyan for day', () {
      expect(getGroupColor(ReportGroupType.day), Colors.cyan);
    });

    test('returns orange for week', () {
      expect(getGroupColor(ReportGroupType.week), Colors.orange);
    });

    test('returns purple for month', () {
      expect(getGroupColor(ReportGroupType.month), Colors.purple);
    });
  });
}

/// Simple test report class with an id and date.
class _TestReport {
  final String id;
  final DateTime date;

  _TestReport(this.id, this.date);
}
