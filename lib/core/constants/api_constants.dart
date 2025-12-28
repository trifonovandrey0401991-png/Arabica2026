class ApiConstants {
  // URL
  static const String serverUrl = 'https://arabica26.ru';

  // Timeouts
  static const Duration shortTimeout = Duration(seconds: 10);
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration longTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);

  // Headers
  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Endpoints
  static const String attendanceEndpoint = '/api/attendance';
  static const String clientsEndpoint = '/api/clients';
  static const String employeesEndpoint = '/api/employees';
  static const String menuEndpoint = '/api/menu';
  static const String ordersEndpoint = '/api/orders';
  static const String recipesEndpoint = '/api/recipes';
  static const String reviewsEndpoint = '/api/reviews';
  static const String rkoEndpoint = '/api/rko';
  static const String shopsEndpoint = '/api/shops';
  static const String workScheduleEndpoint = '/api/work-schedule';
  static const String kpiEndpoint = '/api/kpi';
}
