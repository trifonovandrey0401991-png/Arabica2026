import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/oos_settings_model.dart';
import '../models/oos_table_model.dart';
import '../models/oos_report_model.dart';

/// Service for OOS (Out of Stock) API calls
class OosService {
  static const String _endpoint = '/api/oos';

  /// Get OOS settings (flagged products + interval)
  static Future<OosSettings> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/settings'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return OosSettings.fromJson(data['settings'] ?? {});
      }
    } catch (e) {
      Logger.error('Error getting OOS settings', e);
    }
    return OosSettings();
  }

  /// Save OOS settings
  static Future<bool> saveSettings(OosSettings settings) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/settings'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(settings.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e) {
      Logger.error('Error saving OOS settings', e);
    }
    return false;
  }

  /// Get OOS table (live stock data)
  static Future<({List<OosTableRow> rows, List<OosShopInfo> shops})> getTable() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/table'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rows = (data['rows'] as List? ?? [])
            .map((e) => OosTableRow.fromJson(e))
            .toList();
        final shops = (data['shops'] as List? ?? [])
            .map((e) => OosShopInfo.fromJson(e))
            .toList();
        return (rows: rows, shops: shops);
      }
    } catch (e) {
      Logger.error('Error getting OOS table', e);
    }
    return (rows: <OosTableRow>[], shops: <OosShopInfo>[]);
  }

  /// Get OOS report (monthly summary per shop)
  static Future<({List<OosShopSummary> shops, List<String> availableMonths})> getReport({String? month}) async {
    try {
      var url = '${ApiConstants.serverUrl}$_endpoint/report';
      if (month != null) url += '?month=$month';

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shops = (data['shops'] as List? ?? [])
            .map((e) => OosShopSummary.fromJson(e))
            .toList();
        final months = List<String>.from(data['availableMonths'] ?? []);
        return (shops: shops, availableMonths: months);
      }
    } catch (e) {
      Logger.error('Error getting OOS report', e);
    }
    return (shops: <OosShopSummary>[], availableMonths: <String>[]);
  }

  /// Get detailed OOS report for a shop + month
  static Future<OosReportDetail?> getReportDetail(String shopId, String month) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/report/$shopId/$month'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return OosReportDetail.fromJson(data);
      }
    } catch (e) {
      Logger.error('Error getting OOS report detail', e);
    }
    return null;
  }
}
