import '../models/client_dialog_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ClientDialogService {
  static const String baseEndpoint = ApiConstants.clientDialogsEndpoint;

  /// Получить все диалоги клиента
  static Future<List<ClientDialog>> getClientDialogs(String clientPhone) async {
    Logger.debug('📥 Загрузка диалогов клиента: ${Logger.maskPhone(clientPhone)}');
    return await BaseHttpService.getList<ClientDialog>(
      endpoint: '$baseEndpoint/$clientPhone',
      fromJson: (json) => ClientDialog.fromJson(json),
      listKey: 'dialogs',
    );
  }

  /// Получить диалог по магазину
  static Future<ClientDialog?> getShopDialog(String clientPhone, String shopAddress) async {
    Logger.debug('📥 Загрузка диалога: ${Logger.maskPhone(clientPhone)}, магазин: $shopAddress');
    final encodedShopAddress = Uri.encodeComponent(shopAddress);
    return await BaseHttpService.get<ClientDialog>(
      endpoint: '$baseEndpoint/$clientPhone/shop/$encodedShopAddress',
      fromJson: (json) => ClientDialog.fromJson(json),
      itemKey: 'dialog',
    );
  }
}



