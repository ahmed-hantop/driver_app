import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Driver Dashboard'**
  String get appTitle;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @iqama.
  ///
  /// In en, this message translates to:
  /// **'Iqama Number'**
  String get iqama;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please check your credentials or try again later.'**
  String get loginFailed;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register / Become our delivery driver'**
  String get register;

  /// No description provided for @mapsError.
  ///
  /// In en, this message translates to:
  /// **'Could not open maps'**
  String get mapsError;

  /// No description provided for @mapsPermission.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required for maps'**
  String get mapsPermission;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission denied. Enable it in Settings.'**
  String get cameraPermissionDenied;

  /// No description provided for @cameraPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required.'**
  String get cameraPermissionRequired;

  /// No description provided for @mediaPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Media/photos permission denied. Enable it in Settings.'**
  String get mediaPermissionDenied;

  /// No description provided for @mediaPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Media/photos permission is required.'**
  String get mediaPermissionRequired;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied. Enable it in Settings.'**
  String get locationPermissionDenied;

  /// No description provided for @failedToLoadData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load data. Please try again.'**
  String get failedToLoadData;

  /// No description provided for @unableLoadProfile.
  ///
  /// In en, this message translates to:
  /// **'Unable to load profile'**
  String get unableLoadProfile;

  /// No description provided for @alreadyCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Already checked in'**
  String get alreadyCheckedIn;

  /// No description provided for @meterReadingRequired.
  ///
  /// In en, this message translates to:
  /// **'Meter reading required'**
  String get meterReadingRequired;

  /// No description provided for @meterImageRequired.
  ///
  /// In en, this message translates to:
  /// **'Meter image required'**
  String get meterImageRequired;

  /// No description provided for @checkinSuccess.
  ///
  /// In en, this message translates to:
  /// **'Checked in successfully'**
  String get checkinSuccess;

  /// No description provided for @checkinFailed.
  ///
  /// In en, this message translates to:
  /// **'Check-in failed'**
  String get checkinFailed;

  /// No description provided for @outMeterImageRequired.
  ///
  /// In en, this message translates to:
  /// **'Out meter image required'**
  String get outMeterImageRequired;

  /// No description provided for @checkoutSuccess.
  ///
  /// In en, this message translates to:
  /// **'Checked out successfully'**
  String get checkoutSuccess;

  /// No description provided for @checkoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Check-out failed'**
  String get checkoutFailed;

  /// No description provided for @alreadyCheckedOut.
  ///
  /// In en, this message translates to:
  /// **'Already checked out'**
  String get alreadyCheckedOut;

  /// No description provided for @profileRequired.
  ///
  /// In en, this message translates to:
  /// **'Name and mobile are required'**
  String get profileRequired;

  /// No description provided for @profileUpdateSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdateSuccess;

  /// No description provided for @profileUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Profile update failed'**
  String get profileUpdateFailed;

  /// No description provided for @selectBusinessIdFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a business ID first'**
  String get selectBusinessIdFirst;

  /// No description provided for @orderNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Order number is required'**
  String get orderNumberRequired;

  /// No description provided for @orderCreated.
  ///
  /// In en, this message translates to:
  /// **'Order created'**
  String get orderCreated;

  /// No description provided for @orderCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create order'**
  String get orderCreateFailed;

  /// No description provided for @orderPicked.
  ///
  /// In en, this message translates to:
  /// **'Order picked up'**
  String get orderPicked;

  /// No description provided for @orderPickupFailed.
  ///
  /// In en, this message translates to:
  /// **'Pickup failed'**
  String get orderPickupFailed;

  /// No description provided for @cashAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount received is required for cash'**
  String get cashAmountRequired;

  /// No description provided for @orderDelivered.
  ///
  /// In en, this message translates to:
  /// **'Order delivered'**
  String get orderDelivered;

  /// No description provided for @orderDeliveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Delivery failed'**
  String get orderDeliveryFailed;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get orderCancelled;

  /// No description provided for @orderCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Cancel failed'**
  String get orderCancelFailed;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @checkInOut.
  ///
  /// In en, this message translates to:
  /// **'Check-in/out'**
  String get checkInOut;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @driverNameFallback.
  ///
  /// In en, this message translates to:
  /// **'Driver Name'**
  String get driverNameFallback;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @ordersSelected.
  ///
  /// In en, this message translates to:
  /// **'Orders (selected)'**
  String get ordersSelected;

  /// No description provided for @deliveredPercent.
  ///
  /// In en, this message translates to:
  /// **'Delivered %'**
  String get deliveredPercent;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @pickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get pickup;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @assignedVehicle.
  ///
  /// In en, this message translates to:
  /// **'Assigned Vehicle'**
  String get assignedVehicle;

  /// No description provided for @plate.
  ///
  /// In en, this message translates to:
  /// **'Plate: '**
  String get plate;

  /// No description provided for @requestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get requestsTitle;

  /// No description provided for @requestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fuel & internet recharge requests'**
  String get requestsSubtitle;

  /// No description provided for @businessesAndIds.
  ///
  /// In en, this message translates to:
  /// **'Businesses & IDs'**
  String get businessesAndIds;

  /// No description provided for @checkinRequiredAccess.
  ///
  /// In en, this message translates to:
  /// **'Check-in required to access IDs'**
  String get checkinRequiredAccess;

  /// No description provided for @checkinPrompt.
  ///
  /// In en, this message translates to:
  /// **'Please check-in to unlock assigned business IDs and start orders.'**
  String get checkinPrompt;

  /// No description provided for @goToCheckin.
  ///
  /// In en, this message translates to:
  /// **'Go to Check-in'**
  String get goToCheckin;

  /// No description provided for @noIdsAssigned.
  ///
  /// In en, this message translates to:
  /// **'No IDs assigned yet. Pull to refresh or contact dispatch.'**
  String get noIdsAssigned;

  /// No description provided for @platformId.
  ///
  /// In en, this message translates to:
  /// **'Platform ID: '**
  String get platformId;

  /// No description provided for @currentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current Location'**
  String get currentLocation;

  /// No description provided for @noAddress.
  ///
  /// In en, this message translates to:
  /// **'No address available'**
  String get noAddress;

  /// No description provided for @coordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates: {lat}, {lng}'**
  String coordinates(Object lat, Object lng);

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// No description provided for @ordersHeading.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersHeading;

  /// No description provided for @noOrders.
  ///
  /// In en, this message translates to:
  /// **'No orders found'**
  String get noOrders;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get statusDelivered;

  /// No description provided for @statusPicked.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get statusPicked;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @orderFallback.
  ///
  /// In en, this message translates to:
  /// **'Order {id}'**
  String orderFallback(Object id);

  /// No description provided for @orderNumberValue.
  ///
  /// In en, this message translates to:
  /// **'Order #: {orderNumber}'**
  String orderNumberValue(Object orderNumber);

  /// No description provided for @businessIdValue.
  ///
  /// In en, this message translates to:
  /// **'Business ID: {value}'**
  String businessIdValue(Object value);

  /// No description provided for @pickupTime.
  ///
  /// In en, this message translates to:
  /// **'Pickup: {time}'**
  String pickupTime(Object time);

  /// No description provided for @deliveredTime.
  ///
  /// In en, this message translates to:
  /// **'Delivered: {time}'**
  String deliveredTime(Object time);

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Working...'**
  String get working;

  /// No description provided for @markPickup.
  ///
  /// In en, this message translates to:
  /// **'Mark Pickup'**
  String get markPickup;

  /// No description provided for @deliverAction.
  ///
  /// In en, this message translates to:
  /// **'Deliver'**
  String get deliverAction;

  /// No description provided for @paymentType.
  ///
  /// In en, this message translates to:
  /// **'Payment Type'**
  String get paymentType;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @amountReceivedRequiredCash.
  ///
  /// In en, this message translates to:
  /// **'Amount received (required for cash)'**
  String get amountReceivedRequiredCash;

  /// No description provided for @amountPaidOptional.
  ///
  /// In en, this message translates to:
  /// **'Amount paid (optional)'**
  String get amountPaidOptional;

  /// No description provided for @cancelOrderAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get cancelOrderAction;

  /// No description provided for @cancelReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel reason'**
  String get cancelReasonLabel;

  /// No description provided for @cancelReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Enter reason'**
  String get cancelReasonHint;

  /// No description provided for @cancelReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Reason is required'**
  String get cancelReasonRequired;

  /// No description provided for @cancelReasonTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a cancel reason'**
  String get cancelReasonTypeRequired;

  /// No description provided for @cancelByCustomer.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by customer'**
  String get cancelByCustomer;

  /// No description provided for @cancelByBusiness.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by {businessName}'**
  String cancelByBusiness(Object businessName);

  /// No description provided for @cancelByOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get cancelByOther;

  /// No description provided for @submitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get submitting;

  /// No description provided for @markDelivered.
  ///
  /// In en, this message translates to:
  /// **'Mark Delivered'**
  String get markDelivered;

  /// No description provided for @checkinTitle.
  ///
  /// In en, this message translates to:
  /// **'Check-in'**
  String get checkinTitle;

  /// No description provided for @meterReading.
  ///
  /// In en, this message translates to:
  /// **'Meter Reading'**
  String get meterReading;

  /// No description provided for @meterReadingHintCurrent.
  ///
  /// In en, this message translates to:
  /// **'Enter current meter reading'**
  String get meterReadingHintCurrent;

  /// No description provided for @uploadMeterImage.
  ///
  /// In en, this message translates to:
  /// **'Upload Meter Image'**
  String get uploadMeterImage;

  /// No description provided for @clickSelectImage.
  ///
  /// In en, this message translates to:
  /// **'Click to select image'**
  String get clickSelectImage;

  /// No description provided for @profileTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get profileTakePhoto;

  /// No description provided for @profileChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get profileChooseFile;

  /// No description provided for @checkingIn.
  ///
  /// In en, this message translates to:
  /// **'Checking in...'**
  String get checkingIn;

  /// No description provided for @checkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Check-out'**
  String get checkoutTitle;

  /// No description provided for @meterReadingHintFinal.
  ///
  /// In en, this message translates to:
  /// **'Enter final meter reading'**
  String get meterReadingHintFinal;

  /// No description provided for @checkingOut.
  ///
  /// In en, this message translates to:
  /// **'Checking out...'**
  String get checkingOut;

  /// No description provided for @personalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformation;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @mobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Number'**
  String get mobileNumber;

  /// No description provided for @nationality.
  ///
  /// In en, this message translates to:
  /// **'Nationality'**
  String get nationality;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @leaveBlankPassword.
  ///
  /// In en, this message translates to:
  /// **'Leave blank if you don\'t want to change your password'**
  String get leaveBlankPassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @newOrderFor.
  ///
  /// In en, this message translates to:
  /// **'New Order for {businessName}'**
  String newOrderFor(Object businessName);

  /// No description provided for @businessIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Business ID: {value}'**
  String businessIdLabel(Object value);

  /// No description provided for @orderNumberInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Order Number'**
  String get orderNumberInputLabel;

  /// No description provided for @orderNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Enter order number'**
  String get orderNumberHint;

  /// No description provided for @creating.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get creating;

  /// No description provided for @createOrder.
  ///
  /// In en, this message translates to:
  /// **'Create Order'**
  String get createOrder;

  /// No description provided for @deliverOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Deliver order {orderNumber}'**
  String deliverOrderTitle(Object orderNumber);

  /// No description provided for @splashCheckingUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking updates...'**
  String get splashCheckingUpdates;

  /// No description provided for @splashCheckingVersion.
  ///
  /// In en, this message translates to:
  /// **'Checking app version...'**
  String get splashCheckingVersion;

  /// No description provided for @splashValidatingSession.
  ///
  /// In en, this message translates to:
  /// **'Validating session...'**
  String get splashValidatingSession;

  /// No description provided for @splashOpeningApp.
  ///
  /// In en, this message translates to:
  /// **'Opening app...'**
  String get splashOpeningApp;

  /// No description provided for @splashUpdateCheckFailedOpening.
  ///
  /// In en, this message translates to:
  /// **'Update check failed. Opening app...'**
  String get splashUpdateCheckFailedOpening;

  /// No description provided for @splashUpdatesUnavailableOpening.
  ///
  /// In en, this message translates to:
  /// **'Updates unavailable in this build. Opening app...'**
  String get splashUpdatesUnavailableOpening;

  /// No description provided for @splashUpdateDownloadedRestarting.
  ///
  /// In en, this message translates to:
  /// **'Update downloaded. Restarting app...'**
  String get splashUpdateDownloadedRestarting;

  /// No description provided for @splashUpdateReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Update ready'**
  String get splashUpdateReadyTitle;

  /// No description provided for @splashUpdateReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Latest patch downloaded. App will now close so you can reopen with the update.'**
  String get splashUpdateReadyBody;

  /// No description provided for @forceUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Required'**
  String get forceUpdateTitle;

  /// No description provided for @forceUpdateLinkMissing.
  ///
  /// In en, this message translates to:
  /// **'Update link is not configured on server.'**
  String get forceUpdateLinkMissing;

  /// No description provided for @forceUpdateLinkInvalidConfig.
  ///
  /// In en, this message translates to:
  /// **'Update link is not configured correctly.'**
  String get forceUpdateLinkInvalidConfig;

  /// No description provided for @forceUpdateLinkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the update link.'**
  String get forceUpdateLinkOpenFailed;

  /// No description provided for @forceUpdateLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid update link.'**
  String get forceUpdateLinkInvalid;

  /// No description provided for @forceUpdateOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening...'**
  String get forceUpdateOpening;

  /// No description provided for @forceUpdateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get forceUpdateNow;

  /// No description provided for @forceUpdateBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'This version is blocked. Please update to continue.'**
  String get forceUpdateBlockedMessage;

  /// No description provided for @forceUpdateDefaultMessage.
  ///
  /// In en, this message translates to:
  /// **'A new app version is available. Please update to continue.'**
  String get forceUpdateDefaultMessage;

  /// No description provided for @forceUpdateVersionSummary.
  ///
  /// In en, this message translates to:
  /// **'Current: {currentVersion}  Latest: {latestVersion}'**
  String forceUpdateVersionSummary(Object currentVersion, Object latestVersion);

  /// No description provided for @forgotRecoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Recover your account'**
  String get forgotRecoverTitle;

  /// No description provided for @forgotRecoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your iqama number or email to get a reset code.'**
  String get forgotRecoverSubtitle;

  /// No description provided for @forgotIqamaOrEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Iqama or email'**
  String get forgotIqamaOrEmailLabel;

  /// No description provided for @forgotIqamaOrEmailValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter your iqama or email.'**
  String get forgotIqamaOrEmailValidation;

  /// No description provided for @forgotEnterIqamaOrEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your iqama or email.'**
  String get forgotEnterIqamaOrEmail;

  /// No description provided for @forgotEnterIqamaOrEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter your iqama or email first.'**
  String get forgotEnterIqamaOrEmailFirst;

  /// No description provided for @forgotOtpSent.
  ///
  /// In en, this message translates to:
  /// **'OTP has been sent to your email.'**
  String get forgotOtpSent;

  /// No description provided for @forgotOtpSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send OTP.'**
  String get forgotOtpSendFailed;

  /// No description provided for @forgotEnterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit OTP.'**
  String get forgotEnterOtp;

  /// No description provided for @forgotOtpVerified.
  ///
  /// In en, this message translates to:
  /// **'OTP verified. You can reset your password now.'**
  String get forgotOtpVerified;

  /// No description provided for @forgotOtpVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'OTP verification failed.'**
  String get forgotOtpVerificationFailed;

  /// No description provided for @forgotOtpResent.
  ///
  /// In en, this message translates to:
  /// **'OTP resent. Please check your email.'**
  String get forgotOtpResent;

  /// No description provided for @forgotOtpResendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to resend OTP.'**
  String get forgotOtpResendFailed;

  /// No description provided for @forgotVerifyOtpFirst.
  ///
  /// In en, this message translates to:
  /// **'Verify the OTP first.'**
  String get forgotVerifyOtpFirst;

  /// No description provided for @forgotPasswordResetSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Password has been reset. Please log in with the new password.'**
  String get forgotPasswordResetSuccessMessage;

  /// No description provided for @forgotPasswordResetFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to reset password.'**
  String get forgotPasswordResetFailed;

  /// No description provided for @forgotPasswordResetSnackBar.
  ///
  /// In en, this message translates to:
  /// **'Password reset successfully.'**
  String get forgotPasswordResetSnackBar;

  /// No description provided for @forgotSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get forgotSendOtp;

  /// No description provided for @forgotOtpSentPrompt.
  ///
  /// In en, this message translates to:
  /// **'We sent an OTP to your email. Enter it below to continue.'**
  String get forgotOtpSentPrompt;

  /// No description provided for @forgotOtpLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit OTP'**
  String get forgotOtpLabel;

  /// No description provided for @forgotVerifyOtp.
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get forgotVerifyOtp;

  /// No description provided for @forgotResend.
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get forgotResend;

  /// No description provided for @forgotConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get forgotConfirmPassword;

  /// No description provided for @forgotPasswordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get forgotPasswordMinLength;

  /// No description provided for @forgotPasswordsMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get forgotPasswordsMismatch;

  /// No description provided for @forgotResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get forgotResetPassword;

  /// No description provided for @notificationPickupPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pickup pending'**
  String get notificationPickupPendingTitle;

  /// No description provided for @notificationPickupPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Order {orderNumber} needs pickup.'**
  String notificationPickupPendingBody(Object orderNumber);

  /// No description provided for @notificationDeliveryPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery pending'**
  String get notificationDeliveryPendingTitle;

  /// No description provided for @notificationDeliveryPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Order {orderNumber} needs delivery.'**
  String notificationDeliveryPendingBody(Object orderNumber);

  /// No description provided for @notificationCheckinCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Check-in complete'**
  String get notificationCheckinCompleteTitle;

  /// No description provided for @notificationCheckinCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'You have successfully checked in.'**
  String get notificationCheckinCompleteBody;

  /// No description provided for @notificationCheckoutCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Checkout complete'**
  String get notificationCheckoutCompleteTitle;

  /// No description provided for @notificationCheckoutCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'You have successfully checked out.'**
  String get notificationCheckoutCompleteBody;

  /// No description provided for @notificationOrderQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order queued'**
  String get notificationOrderQueuedTitle;

  /// No description provided for @notificationOrderQueuedBody.
  ///
  /// In en, this message translates to:
  /// **'Order {orderNumber} saved. Sync will run automatically.'**
  String notificationOrderQueuedBody(Object orderNumber);

  /// No description provided for @notificationOrderPickupQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order pickup queued'**
  String get notificationOrderPickupQueuedTitle;

  /// No description provided for @notificationOrderDeliveryQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order delivery queued'**
  String get notificationOrderDeliveryQueuedTitle;

  /// No description provided for @notificationOrderSavedForSyncBody.
  ///
  /// In en, this message translates to:
  /// **'Order {orderNumber} saved for sync.'**
  String notificationOrderSavedForSyncBody(Object orderNumber);

  /// No description provided for @toastOrderQueuedLocalSync.
  ///
  /// In en, this message translates to:
  /// **'Order queued and saved locally. It will sync within 5 minutes.'**
  String get toastOrderQueuedLocalSync;

  /// No description provided for @toastPickupQueued.
  ///
  /// In en, this message translates to:
  /// **'Pickup queued. Sync will run automatically (max 5 min).'**
  String get toastPickupQueued;

  /// No description provided for @toastCancellationQueued.
  ///
  /// In en, this message translates to:
  /// **'Cancellation queued. Sync will run automatically (max 5 min).'**
  String get toastCancellationQueued;

  /// No description provided for @toastDeliveryQueued.
  ///
  /// In en, this message translates to:
  /// **'Delivery queued. Sync will run automatically (max 5 min).'**
  String get toastDeliveryQueued;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
