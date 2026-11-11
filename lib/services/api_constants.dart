class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dms.speedlogi.sa/api/v1',
  );
  static const String publicBaseUrl = String.fromEnvironment(
    'PUBLIC_BASE_URL',
    defaultValue: 'https://dms.speedlogi.sa',
  );
  static const String publicHost = String.fromEnvironment(
    'PUBLIC_HOST',
    defaultValue: 'dms.speedlogi.sa',
  );
  static const String publicStorageBaseUrl = '$publicBaseUrl/storage';
  static const String login = '/auth/login';
  static const String checkin = '/auth/checkin';
  static const String checkout = '/auth/checkout';
  static const String logout = '/auth/logout';
  static const String updateFcmToken = '/auth/fcm-token';
  static const String forgotPassword = '/auth/forgot-password';
  static const String verifyResetToken = '/auth/verify-reset-token';
  static const String resetPassword = '/auth/reset-password';
  static const String resendResetLink = '/auth/resend-reset-link';
  static const String profile = '/profile';
  static const String location = '/location';
  static const String heartbeat = '/heartbeat';
  static const String businesses = '/profile/businesses';
  static const String stats = '/profile/stats';
  static const String uniqueOrderBusiness = '/profile/get-unique-order-business';
  static const String orders = '/order';
  static const String orderReminders = '/order/reminders';
  static const String orderPickup = '/order/pickup';
  static const String orderCancel = '/order/cancel';
  static const String appLogs = '/app-logs';
  static const String remoteDiagnosticEvent = 'remote_diagnostic_result';
  static const String appVersionPolicy   = '/app/version';
  // Payroll
  static const String payrollSlips       = '/payroll/slips';
  // Chat
  static const String chatConversations  = '/chat/conversations';
  static const String chatUnreadCount    = '/chat/unread-count';
  // Calls
  static const String callsPending       = '/calls/pending';
  static const String callsHistory       = '/calls/history';
  // Requests
  static const String fuelRequests       = '/fuel';
  static const String rechargeRequests   = '/recharge';
}