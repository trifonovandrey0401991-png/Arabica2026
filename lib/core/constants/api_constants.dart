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

  // Endpoints - Core
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

  // Endpoints - Employees & Registration
  static const String employeeRegistrationEndpoint = '/api/employee-registration';
  static const String employeeRegistrationsEndpoint = '/api/employee-registrations';
  static const String employeeChatsEndpoint = '/api/employee-chats';

  // Endpoints - Clients & Dialogs
  static const String clientDialogsEndpoint = '/api/client-dialogs';

  // Endpoints - Shifts & Reports
  static const String shiftReportsEndpoint = '/api/shift-reports';
  static const String shiftQuestionsEndpoint = '/api/shift-questions';
  static const String pendingShiftReportsEndpoint = '/api/pending-shift-reports';
  static const String shiftTransfersEndpoint = '/api/shift-transfers';
  static const String shiftHandoverReportsEndpoint = '/api/shift-handover-reports';
  static const String shiftHandoverQuestionsEndpoint = '/api/shift-handover-questions';
  static const String pendingShiftHandoverReportsEndpoint = '/api/pending-shift-handover-reports';

  // Endpoints - Recount
  static const String recountReportsEndpoint = '/api/recount-reports';
  static const String recountQuestionsEndpoint = '/api/recount-questions';
  static const String recountPointsEndpoint = '/api/recount-points';
  static const String recountSettingsEndpoint = '/api/recount-settings';
  static const String pendingRecountReportsEndpoint = '/api/pending-recount-reports';

  // Endpoints - Envelope
  static const String envelopeReportsEndpoint = '/api/envelope-reports';
  static const String envelopeQuestionsEndpoint = '/api/envelope-questions';

  // Endpoints - Tests & Training
  static const String testQuestionsEndpoint = '/api/test-questions';
  static const String testResultsEndpoint = '/api/test-results';
  static const String trainingArticlesEndpoint = '/api/training-articles';

  // Endpoints - Efficiency & Points
  static const String pointsSettingsEndpoint = '/api/points-settings';
  static const String efficiencyPenaltiesEndpoint = '/api/efficiency-penalties';
  static const String efficiencyReportsBatchEndpoint = '/api/efficiency/reports-batch';
  static const String bonusPenaltiesEndpoint = '/api/bonus-penalties';

  // Endpoints - Tasks
  static const String tasksEndpoint = '/api/tasks';
  static const String taskAssignmentsEndpoint = '/api/task-assignments';
  static const String recurringTasksEndpoint = '/api/recurring-tasks';

  // Endpoints - Cash & Withdrawals
  static const String withdrawalsEndpoint = '/api/withdrawals';

  // Endpoints - Fortune Wheel & Rating
  static const String fortuneWheelEndpoint = '/api/fortune-wheel';
  static const String ratingsEndpoint = '/api/ratings';

  // Endpoints - Referrals & Job Applications
  static const String referralsEndpoint = '/api/referrals';
  static const String jobApplicationsEndpoint = '/api/job-applications';

  // Endpoints - Suppliers & Product Questions
  static const String suppliersEndpoint = '/api/suppliers';
  static const String productQuestionsEndpoint = '/api/product-questions';
  static const String productQuestionDialogsEndpoint = '/api/product-question-dialogs';

  // Endpoints - Settings
  static const String shopSettingsEndpoint = '/api/shop-settings';
  static const String fcmTokensEndpoint = '/api/fcm-tokens';
  static const String loyaltyPromoEndpoint = '/api/loyalty-promo';

  // Endpoints - Cigarette Vision (AI Training)
  // Теперь товары берутся из мастер-каталога
  static const String cigaretteProductsEndpoint = '/api/master-catalog/for-training';
  static const String cigaretteTrainingSamplesEndpoint = '/api/cigarette-vision/samples';
  static const String cigaretteStatsEndpoint = '/api/cigarette-vision/stats';
  static const String cigaretteDetectEndpoint = '/api/cigarette-vision/detect';
  static const String cigaretteDisplayCheckEndpoint = '/api/cigarette-vision/display-check';
}
