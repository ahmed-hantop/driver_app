// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Driver Dashboard';

  @override
  String get english => 'English';

  @override
  String get arabic => 'Arabic';

  @override
  String get iqama => 'Iqama Number';

  @override
  String get password => 'Password';

  @override
  String get login => 'Login';

  @override
  String get loginFailed =>
      'Login failed. Please check your credentials or try again later.';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get register => 'Register / Become our delivery driver';

  @override
  String get mapsError => 'Could not open maps';

  @override
  String get mapsPermission => 'Location permission is required for maps';

  @override
  String get cameraPermissionDenied =>
      'Camera permission denied. Enable it in Settings.';

  @override
  String get cameraPermissionRequired => 'Camera permission is required.';

  @override
  String get mediaPermissionDenied =>
      'Media/photos permission denied. Enable it in Settings.';

  @override
  String get mediaPermissionRequired => 'Media/photos permission is required.';

  @override
  String get locationPermissionDenied =>
      'Location permission denied. Enable it in Settings.';

  @override
  String get failedToLoadData => 'Failed to load data. Please try again.';

  @override
  String get unableLoadProfile => 'Unable to load profile';

  @override
  String get alreadyCheckedIn => 'Already checked in';

  @override
  String get meterReadingRequired => 'Meter reading required';

  @override
  String get meterImageRequired => 'Meter image required';

  @override
  String get checkinSuccess => 'Checked in successfully';

  @override
  String get checkinFailed => 'Check-in failed';

  @override
  String get outMeterImageRequired => 'Out meter image required';

  @override
  String get checkoutSuccess => 'Checked out successfully';

  @override
  String get checkoutFailed => 'Check-out failed';

  @override
  String get alreadyCheckedOut => 'Already checked out';

  @override
  String get profileRequired => 'Name and mobile are required';

  @override
  String get profileUpdateSuccess => 'Profile updated';

  @override
  String get profileUpdateFailed => 'Profile update failed';

  @override
  String get selectBusinessIdFirst => 'Select a business ID first';

  @override
  String get orderNumberRequired => 'Order number is required';

  @override
  String get orderCreated => 'Order created';

  @override
  String get orderCreateFailed => 'Failed to create order';

  @override
  String get orderPicked => 'Order picked up';

  @override
  String get orderPickupFailed => 'Pickup failed';

  @override
  String get cashAmountRequired => 'Amount received is required for cash';

  @override
  String get orderDelivered => 'Order delivered';

  @override
  String get orderDeliveryFailed => 'Delivery failed';

  @override
  String get orderCancelled => 'Order cancelled';

  @override
  String get orderCancelFailed => 'Cancel failed';

  @override
  String get home => 'Home';

  @override
  String get orders => 'Orders';

  @override
  String get checkInOut => 'Check-in/out';

  @override
  String get profile => 'Profile';

  @override
  String get driverNameFallback => 'Driver Name';

  @override
  String get unknown => 'Unknown';

  @override
  String get logout => 'Logout';

  @override
  String get ordersSelected => 'Orders (selected)';

  @override
  String get deliveredPercent => 'Delivered %';

  @override
  String get delivered => 'Delivered';

  @override
  String get pickup => 'Pickup';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get thisMonth => 'This Month';

  @override
  String get assignedVehicle => 'Assigned Vehicle';

  @override
  String get plate => 'Plate: ';

  @override
  String get requestsTitle => 'Requests';

  @override
  String get requestsSubtitle => 'Fuel & internet recharge requests';

  @override
  String get businessesAndIds => 'Businesses & IDs';

  @override
  String get checkinRequiredAccess => 'Check-in required to access IDs';

  @override
  String get checkinPrompt =>
      'Please check-in to unlock assigned business IDs and start orders.';

  @override
  String get goToCheckin => 'Go to Check-in';

  @override
  String get noIdsAssigned =>
      'No IDs assigned yet. Pull to refresh or contact dispatch.';

  @override
  String get platformId => 'Platform ID: ';

  @override
  String get currentLocation => 'Current Location';

  @override
  String get noAddress => 'No address available';

  @override
  String coordinates(Object lat, Object lng) {
    return 'Coordinates: $lat, $lng';
  }

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get ordersHeading => 'Orders';

  @override
  String get noOrders => 'No orders found';

  @override
  String get active => 'Active';

  @override
  String get completed => 'Completed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusDelivered => 'Delivered';

  @override
  String get statusPicked => 'Picked up';

  @override
  String get statusPending => 'Pending';

  @override
  String orderFallback(Object id) {
    return 'Order $id';
  }

  @override
  String orderNumberValue(Object orderNumber) {
    return 'Order #: $orderNumber';
  }

  @override
  String businessIdValue(Object value) {
    return 'Business ID: $value';
  }

  @override
  String pickupTime(Object time) {
    return 'Pickup: $time';
  }

  @override
  String deliveredTime(Object time) {
    return 'Delivered: $time';
  }

  @override
  String get working => 'Working...';

  @override
  String get markPickup => 'Mark Pickup';

  @override
  String get deliverAction => 'Deliver';

  @override
  String get paymentType => 'Payment Type';

  @override
  String get wallet => 'Wallet';

  @override
  String get cash => 'Cash';

  @override
  String get online => 'Online';

  @override
  String get amountReceivedRequiredCash =>
      'Amount received (required for cash)';

  @override
  String get amountPaidOptional => 'Amount paid (optional)';

  @override
  String get cancelOrderAction => 'Cancel Order';

  @override
  String get cancelReasonLabel => 'Cancel reason';

  @override
  String get cancelReasonHint => 'Enter reason';

  @override
  String get cancelReasonRequired => 'Reason is required';

  @override
  String get cancelReasonTypeRequired => 'Select a cancel reason';

  @override
  String get cancelByCustomer => 'Cancelled by customer';

  @override
  String cancelByBusiness(Object businessName) {
    return 'Cancelled by $businessName';
  }

  @override
  String get cancelByOther => 'Other';

  @override
  String get submitting => 'Submitting...';

  @override
  String get markDelivered => 'Mark Delivered';

  @override
  String get checkinTitle => 'Check-in';

  @override
  String get meterReading => 'Meter Reading';

  @override
  String get meterReadingHintCurrent => 'Enter current meter reading';

  @override
  String get uploadMeterImage => 'Upload Meter Image';

  @override
  String get clickSelectImage => 'Click to select image';

  @override
  String get profileTakePhoto => 'Take photo';

  @override
  String get profileChooseFile => 'Choose file';

  @override
  String get checkingIn => 'Checking in...';

  @override
  String get checkoutTitle => 'Check-out';

  @override
  String get meterReadingHintFinal => 'Enter final meter reading';

  @override
  String get checkingOut => 'Checking out...';

  @override
  String get personalInformation => 'Personal Information';

  @override
  String get fullName => 'Full Name';

  @override
  String get mobileNumber => 'Mobile Number';

  @override
  String get nationality => 'Nationality';

  @override
  String get language => 'Language';

  @override
  String get changePassword => 'Change Password';

  @override
  String get leaveBlankPassword =>
      'Leave blank if you don\'t want to change your password';

  @override
  String get currentPassword => 'Current Password';

  @override
  String get newPassword => 'New Password';

  @override
  String get confirmNewPassword => 'Confirm New Password';

  @override
  String get saving => 'Saving...';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String newOrderFor(Object businessName) {
    return 'New Order for $businessName';
  }

  @override
  String businessIdLabel(Object value) {
    return 'Business ID: $value';
  }

  @override
  String get orderNumberInputLabel => 'Order Number';

  @override
  String get orderNumberHint => 'Enter order number';

  @override
  String get creating => 'Creating...';

  @override
  String get createOrder => 'Create Order';

  @override
  String deliverOrderTitle(Object orderNumber) {
    return 'Deliver order $orderNumber';
  }

  @override
  String get splashCheckingUpdates => 'Checking updates...';

  @override
  String get splashCheckingVersion => 'Checking app version...';

  @override
  String get splashValidatingSession => 'Validating session...';

  @override
  String get splashOpeningApp => 'Opening app...';

  @override
  String get splashUpdateCheckFailedOpening =>
      'Update check failed. Opening app...';

  @override
  String get splashUpdatesUnavailableOpening =>
      'Updates unavailable in this build. Opening app...';

  @override
  String get splashUpdateDownloadedRestarting =>
      'Update downloaded. Restarting app...';

  @override
  String get splashUpdateReadyTitle => 'Update ready';

  @override
  String get splashUpdateReadyBody =>
      'Latest patch downloaded. App will now close so you can reopen with the update.';

  @override
  String get forceUpdateTitle => 'Update Required';

  @override
  String get forceUpdateLinkMissing =>
      'Update link is not configured on server.';

  @override
  String get forceUpdateLinkInvalidConfig =>
      'Update link is not configured correctly.';

  @override
  String get forceUpdateLinkOpenFailed => 'Could not open the update link.';

  @override
  String get forceUpdateLinkInvalid => 'Invalid update link.';

  @override
  String get forceUpdateOpening => 'Opening...';

  @override
  String get forceUpdateNow => 'Update Now';

  @override
  String get forceUpdateBlockedMessage =>
      'This version is blocked. Please update to continue.';

  @override
  String get forceUpdateDefaultMessage =>
      'A new app version is available. Please update to continue.';

  @override
  String forceUpdateVersionSummary(
    Object currentVersion,
    Object latestVersion,
  ) {
    return 'Current: $currentVersion  Latest: $latestVersion';
  }

  @override
  String get forgotRecoverTitle => 'Recover your account';

  @override
  String get forgotRecoverSubtitle =>
      'Enter your iqama number or email to get a reset code.';

  @override
  String get forgotIqamaOrEmailLabel => 'Iqama or email';

  @override
  String get forgotIqamaOrEmailValidation =>
      'Please enter your iqama or email.';

  @override
  String get forgotEnterIqamaOrEmail => 'Enter your iqama or email.';

  @override
  String get forgotEnterIqamaOrEmailFirst => 'Enter your iqama or email first.';

  @override
  String get forgotOtpSent => 'OTP has been sent to your email.';

  @override
  String get forgotOtpSendFailed => 'Unable to send OTP.';

  @override
  String get forgotEnterOtp => 'Enter the 6-digit OTP.';

  @override
  String get forgotOtpVerified =>
      'OTP verified. You can reset your password now.';

  @override
  String get forgotOtpVerificationFailed => 'OTP verification failed.';

  @override
  String get forgotOtpResent => 'OTP resent. Please check your email.';

  @override
  String get forgotOtpResendFailed => 'Unable to resend OTP.';

  @override
  String get forgotVerifyOtpFirst => 'Verify the OTP first.';

  @override
  String get forgotPasswordResetSuccessMessage =>
      'Password has been reset. Please log in with the new password.';

  @override
  String get forgotPasswordResetFailed => 'Unable to reset password.';

  @override
  String get forgotPasswordResetSnackBar => 'Password reset successfully.';

  @override
  String get forgotSendOtp => 'Send OTP';

  @override
  String get forgotOtpSentPrompt =>
      'We sent an OTP to your email. Enter it below to continue.';

  @override
  String get forgotOtpLabel => '6-digit OTP';

  @override
  String get forgotVerifyOtp => 'Verify OTP';

  @override
  String get forgotResend => 'Resend';

  @override
  String get forgotConfirmPassword => 'Confirm password';

  @override
  String get forgotPasswordMinLength =>
      'Password must be at least 8 characters.';

  @override
  String get forgotPasswordsMismatch => 'Passwords do not match.';

  @override
  String get forgotResetPassword => 'Reset password';

  @override
  String get notificationPickupPendingTitle => 'Pickup pending';

  @override
  String notificationPickupPendingBody(Object orderNumber) {
    return 'Order $orderNumber needs pickup.';
  }

  @override
  String get notificationDeliveryPendingTitle => 'Delivery pending';

  @override
  String notificationDeliveryPendingBody(Object orderNumber) {
    return 'Order $orderNumber needs delivery.';
  }

  @override
  String get notificationCheckinCompleteTitle => 'Check-in complete';

  @override
  String get notificationCheckinCompleteBody =>
      'You have successfully checked in.';

  @override
  String get notificationCheckoutCompleteTitle => 'Checkout complete';

  @override
  String get notificationCheckoutCompleteBody =>
      'You have successfully checked out.';

  @override
  String get notificationOrderQueuedTitle => 'Order queued';

  @override
  String notificationOrderQueuedBody(Object orderNumber) {
    return 'Order $orderNumber saved. Sync will run automatically.';
  }

  @override
  String get notificationOrderPickupQueuedTitle => 'Order pickup queued';

  @override
  String get notificationOrderDeliveryQueuedTitle => 'Order delivery queued';

  @override
  String notificationOrderSavedForSyncBody(Object orderNumber) {
    return 'Order $orderNumber saved for sync.';
  }

  @override
  String get toastOrderQueuedLocalSync =>
      'Order queued and saved locally. It will sync within 5 minutes.';

  @override
  String get toastPickupQueued =>
      'Pickup queued. Sync will run automatically (max 5 min).';

  @override
  String get toastCancellationQueued =>
      'Cancellation queued. Sync will run automatically (max 5 min).';

  @override
  String get toastDeliveryQueued =>
      'Delivery queued. Sync will run automatically (max 5 min).';
}
