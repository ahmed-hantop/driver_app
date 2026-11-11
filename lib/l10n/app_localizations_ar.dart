// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'لوحة السائق';

  @override
  String get english => 'الإنجليزية';

  @override
  String get arabic => 'العربية';

  @override
  String get iqama => 'رقم الإقامة';

  @override
  String get password => 'كلمة المرور';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get loginFailed => 'فشل تسجيل الدخول. يرجى التحقق من البيانات.';

  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get register => 'سجل / كن سائق توصيل';

  @override
  String get mapsError => 'تعذر فتح الخرائط';

  @override
  String get mapsPermission => 'مطلوب إذن الموقع للخرائط';

  @override
  String get cameraPermissionDenied =>
      'تم رفض إذن الكاميرا. قم بتمكينه من الإعدادات.';

  @override
  String get cameraPermissionRequired => 'إذن الكاميرا مطلوب.';

  @override
  String get mediaPermissionDenied =>
      'تم رفض إذن الصور/الوسائط. قم بتمكينه من الإعدادات.';

  @override
  String get mediaPermissionRequired => 'مطلوب إذن الصور/الوسائط.';

  @override
  String get locationPermissionDenied =>
      'تم رفض إذن الموقع. قم بتمكينه من الإعدادات.';

  @override
  String get failedToLoadData => 'فشل تحميل البيانات. يرجى المحاولة مرة أخرى.';

  @override
  String get unableLoadProfile => 'تعذر تحميل الملف الشخصي';

  @override
  String get alreadyCheckedIn => 'تم تسجيل الحضور بالفعل';

  @override
  String get meterReadingRequired => 'مطلوب إدخال قراءة العداد';

  @override
  String get meterImageRequired => 'صورة العداد مطلوبة';

  @override
  String get checkinSuccess => 'تم تسجيل الحضور بنجاح';

  @override
  String get checkinFailed => 'فشل تسجيل الحضور';

  @override
  String get outMeterImageRequired => 'مطلوب صورة عداد الخروج';

  @override
  String get checkoutSuccess => 'تم إنهاء الحضور بنجاح';

  @override
  String get checkoutFailed => 'فشل إنهاء الحضور';

  @override
  String get alreadyCheckedOut => 'تم إنهاء الحضور بالفعل';

  @override
  String get profileRequired => 'الاسم ورقم الجوال مطلوبان';

  @override
  String get profileUpdateSuccess => 'تم تحديث الملف الشخصي';

  @override
  String get profileUpdateFailed => 'فشل تحديث الملف الشخصي';

  @override
  String get selectBusinessIdFirst => 'اختر معرف النشاط أولاً';

  @override
  String get orderNumberRequired => 'رقم الطلب مطلوب';

  @override
  String get orderCreated => 'تم إنشاء الطلب';

  @override
  String get orderCreateFailed => 'فشل إنشاء الطلب';

  @override
  String get orderPicked => 'تم استلام الطلب';

  @override
  String get orderPickupFailed => 'فشل الاستلام';

  @override
  String get cashAmountRequired => 'المبلغ المستلم مطلوب للدفع النقدي';

  @override
  String get orderDelivered => 'تم تسليم الطلب';

  @override
  String get orderDeliveryFailed => 'فشل التسليم';

  @override
  String get orderCancelled => 'تم إلغاء الطلب';

  @override
  String get orderCancelFailed => 'تعذر الإلغاء';

  @override
  String get home => 'الرئيسية';

  @override
  String get orders => 'الطلبات';

  @override
  String get checkInOut => 'تسجيل الدخول/الخروج';

  @override
  String get profile => 'الملف الشخصي';

  @override
  String get driverNameFallback => 'اسم السائق';

  @override
  String get unknown => 'غير معروف';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get ordersSelected => 'الطلبات (المحددة)';

  @override
  String get deliveredPercent => 'نسبة التسليم';

  @override
  String get delivered => 'تم التسليم';

  @override
  String get pickup => 'تم الاستلام';

  @override
  String get cancelled => 'تم الإلغاء';

  @override
  String get thisMonth => 'هذا الشهر';

  @override
  String get assignedVehicle => 'المركبة المخصصة';

  @override
  String get plate => 'رقم اللوحة: ';

  @override
  String get requestsTitle => 'الطلبات';

  @override
  String get requestsSubtitle => 'طلبات الوقود وشحن الإنترنت';

  @override
  String get businessesAndIds => 'المتاجر والمعرّفات';

  @override
  String get checkinRequiredAccess => 'يجب تسجيل الحضور للوصول إلى المعرّفات';

  @override
  String get checkinPrompt =>
      'يرجى تسجيل الحضور لفتح معرفات الأعمال المخصصة والبدء في الطلبات.';

  @override
  String get goToCheckin => 'الانتقال إلى تسجيل الحضور';

  @override
  String get noIdsAssigned =>
      'لا توجد معرفات مخصصة بعد. اسحب للتحديث أو تواصل مع المشرف.';

  @override
  String get platformId => 'معرف المنصة: ';

  @override
  String get currentLocation => 'الموقع الحالي';

  @override
  String get noAddress => 'لا يوجد عنوان متاح';

  @override
  String coordinates(Object lat, Object lng) {
    return 'الإحداثيات: $lat, $lng';
  }

  @override
  String get openInMaps => 'فتح في الخرائط';

  @override
  String get ordersHeading => 'الطلبات';

  @override
  String get noOrders => 'لا توجد طلبات';

  @override
  String get active => 'نشط';

  @override
  String get completed => 'مكتمل';

  @override
  String get statusCancelled => 'ملغي';

  @override
  String get statusDelivered => 'تم التسليم';

  @override
  String get statusPicked => 'تم الاستلام';

  @override
  String get statusPending => 'قيد الانتظار';

  @override
  String orderFallback(Object id) {
    return 'طلب $id';
  }

  @override
  String orderNumberValue(Object orderNumber) {
    return 'رقم الطلب: $orderNumber';
  }

  @override
  String businessIdValue(Object value) {
    return 'معرف المتجر: $value';
  }

  @override
  String pickupTime(Object time) {
    return 'وقت الاستلام: $time';
  }

  @override
  String deliveredTime(Object time) {
    return 'وقت التسليم: $time';
  }

  @override
  String get working => 'جارٍ العمل...';

  @override
  String get markPickup => 'تسجيل الاستلام';

  @override
  String get deliverAction => 'تسليم';

  @override
  String get paymentType => 'نوع الدفع';

  @override
  String get wallet => 'المحفظة';

  @override
  String get cash => 'نقداً';

  @override
  String get online => 'إلكتروني';

  @override
  String get amountReceivedRequiredCash =>
      'المبلغ المستلم (مطلوب للدفع النقدي)';

  @override
  String get amountPaidOptional => 'المبلغ المدفوع (اختياري)';

  @override
  String get cancelOrderAction => 'إلغاء الطلب';

  @override
  String get cancelReasonLabel => 'سبب الإلغاء';

  @override
  String get cancelReasonHint => 'أدخل السبب';

  @override
  String get cancelReasonRequired => 'السبب مطلوب';

  @override
  String get cancelReasonTypeRequired => 'يرجى اختيار سبب الإلغاء';

  @override
  String get cancelByCustomer => 'ألغى العميل الطلب';

  @override
  String cancelByBusiness(Object businessName) {
    return 'أُلغي من $businessName';
  }

  @override
  String get cancelByOther => 'سبب آخر';

  @override
  String get submitting => 'جاري الإرسال...';

  @override
  String get markDelivered => 'تسجيل التسليم';

  @override
  String get checkinTitle => 'تسجيل الحضور';

  @override
  String get meterReading => 'قراءة العداد';

  @override
  String get meterReadingHintCurrent => 'أدخل قراءة العداد الحالية';

  @override
  String get uploadMeterImage => 'ارفع صورة العداد';

  @override
  String get clickSelectImage => 'اضغط لاختيار صورة';

  @override
  String get profileTakePhoto => 'التقاط صورة';

  @override
  String get profileChooseFile => 'اختيار ملف';

  @override
  String get checkingIn => 'جاري تسجيل الحضور...';

  @override
  String get checkoutTitle => 'تسجيل الخروج';

  @override
  String get meterReadingHintFinal => 'أدخل قراءة العداد النهائية';

  @override
  String get checkingOut => 'جاري تسجيل الخروج...';

  @override
  String get personalInformation => 'المعلومات الشخصية';

  @override
  String get fullName => 'الاسم الكامل';

  @override
  String get mobileNumber => 'رقم الجوال';

  @override
  String get nationality => 'الجنسية';

  @override
  String get language => 'اللغة';

  @override
  String get changePassword => 'تغيير كلمة المرور';

  @override
  String get leaveBlankPassword =>
      'اترك الحقول فارغة إذا لا تريد تغيير كلمة المرور';

  @override
  String get currentPassword => 'كلمة المرور الحالية';

  @override
  String get newPassword => 'كلمة المرور الجديدة';

  @override
  String get confirmNewPassword => 'تأكيد كلمة المرور الجديدة';

  @override
  String get saving => 'جاري الحفظ...';

  @override
  String get saveChanges => 'حفظ التغييرات';

  @override
  String newOrderFor(Object businessName) {
    return 'طلب جديد لـ $businessName';
  }

  @override
  String businessIdLabel(Object value) {
    return 'معرف المتجر: $value';
  }

  @override
  String get orderNumberInputLabel => 'رقم الطلب';

  @override
  String get orderNumberHint => 'أدخل رقم الطلب';

  @override
  String get creating => 'جاري الإنشاء...';

  @override
  String get createOrder => 'إنشاء طلب';

  @override
  String deliverOrderTitle(Object orderNumber) {
    return 'تسليم الطلب $orderNumber';
  }

  @override
  String get splashCheckingUpdates => 'جارٍ التحقق من التحديثات...';

  @override
  String get splashCheckingVersion => 'جارٍ التحقق من إصدار التطبيق...';

  @override
  String get splashValidatingSession => 'جارٍ التحقق من الجلسة...';

  @override
  String get splashOpeningApp => 'جارٍ فتح التطبيق...';

  @override
  String get splashUpdateCheckFailedOpening =>
      'فشل التحقق من التحديث. جارٍ فتح التطبيق...';

  @override
  String get splashUpdatesUnavailableOpening =>
      'التحديثات غير متاحة في هذه النسخة. جارٍ فتح التطبيق...';

  @override
  String get splashUpdateDownloadedRestarting =>
      'تم تنزيل التحديث. جارٍ إعادة تشغيل التطبيق...';

  @override
  String get splashUpdateReadyTitle => 'التحديث جاهز';

  @override
  String get splashUpdateReadyBody =>
      'تم تنزيل آخر تحديث. سيتم إغلاق التطبيق الآن حتى تتمكن من إعادة فتحه بالتحديث الجديد.';

  @override
  String get forceUpdateTitle => 'التحديث مطلوب';

  @override
  String get forceUpdateLinkMissing => 'رابط التحديث غير مُعد على الخادم.';

  @override
  String get forceUpdateLinkInvalidConfig => 'رابط التحديث غير مُعد بشكل صحيح.';

  @override
  String get forceUpdateLinkOpenFailed => 'تعذر فتح رابط التحديث.';

  @override
  String get forceUpdateLinkInvalid => 'رابط التحديث غير صالح.';

  @override
  String get forceUpdateOpening => 'جارٍ الفتح...';

  @override
  String get forceUpdateNow => 'حدّث الآن';

  @override
  String get forceUpdateBlockedMessage =>
      'تم حظر هذه النسخة. يرجى التحديث للمتابعة.';

  @override
  String get forceUpdateDefaultMessage =>
      'يتوفر إصدار جديد من التطبيق. يرجى التحديث للمتابعة.';

  @override
  String forceUpdateVersionSummary(
    Object currentVersion,
    Object latestVersion,
  ) {
    return 'الحالي: $currentVersion  الأحدث: $latestVersion';
  }

  @override
  String get forgotRecoverTitle => 'استعادة حسابك';

  @override
  String get forgotRecoverSubtitle =>
      'أدخل رقم الإقامة أو البريد الإلكتروني للحصول على رمز إعادة التعيين.';

  @override
  String get forgotIqamaOrEmailLabel => 'رقم الإقامة أو البريد الإلكتروني';

  @override
  String get forgotIqamaOrEmailValidation =>
      'يرجى إدخال رقم الإقامة أو البريد الإلكتروني.';

  @override
  String get forgotEnterIqamaOrEmail =>
      'أدخل رقم الإقامة أو البريد الإلكتروني.';

  @override
  String get forgotEnterIqamaOrEmailFirst =>
      'أدخل رقم الإقامة أو البريد الإلكتروني أولاً.';

  @override
  String get forgotOtpSent => 'تم إرسال رمز التحقق إلى بريدك الإلكتروني.';

  @override
  String get forgotOtpSendFailed => 'تعذر إرسال رمز التحقق.';

  @override
  String get forgotEnterOtp => 'أدخل رمز التحقق المكون من 6 أرقام.';

  @override
  String get forgotOtpVerified =>
      'تم التحقق من رمز التحقق. يمكنك الآن إعادة تعيين كلمة المرور.';

  @override
  String get forgotOtpVerificationFailed => 'فشل التحقق من رمز التحقق.';

  @override
  String get forgotOtpResent =>
      'تمت إعادة إرسال رمز التحقق. يرجى التحقق من بريدك الإلكتروني.';

  @override
  String get forgotOtpResendFailed => 'تعذر إعادة إرسال رمز التحقق.';

  @override
  String get forgotVerifyOtpFirst => 'تحقق من رمز التحقق أولاً.';

  @override
  String get forgotPasswordResetSuccessMessage =>
      'تمت إعادة تعيين كلمة المرور. يرجى تسجيل الدخول بكلمة المرور الجديدة.';

  @override
  String get forgotPasswordResetFailed => 'تعذر إعادة تعيين كلمة المرور.';

  @override
  String get forgotPasswordResetSnackBar =>
      'تمت إعادة تعيين كلمة المرور بنجاح.';

  @override
  String get forgotSendOtp => 'إرسال رمز التحقق';

  @override
  String get forgotOtpSentPrompt =>
      'أرسلنا رمز تحقق إلى بريدك الإلكتروني. أدخله أدناه للمتابعة.';

  @override
  String get forgotOtpLabel => 'رمز تحقق من 6 أرقام';

  @override
  String get forgotVerifyOtp => 'التحقق من الرمز';

  @override
  String get forgotResend => 'إعادة الإرسال';

  @override
  String get forgotConfirmPassword => 'تأكيد كلمة المرور';

  @override
  String get forgotPasswordMinLength =>
      'يجب أن تكون كلمة المرور 8 أحرف على الأقل.';

  @override
  String get forgotPasswordsMismatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get forgotResetPassword => 'إعادة تعيين كلمة المرور';

  @override
  String get notificationPickupPendingTitle => 'الاستلام معلق';

  @override
  String notificationPickupPendingBody(Object orderNumber) {
    return 'الطلب $orderNumber يحتاج إلى استلام.';
  }

  @override
  String get notificationDeliveryPendingTitle => 'التسليم معلق';

  @override
  String notificationDeliveryPendingBody(Object orderNumber) {
    return 'الطلب $orderNumber يحتاج إلى تسليم.';
  }

  @override
  String get notificationCheckinCompleteTitle => 'اكتمل تسجيل الحضور';

  @override
  String get notificationCheckinCompleteBody => 'تم تسجيل حضورك بنجاح.';

  @override
  String get notificationCheckoutCompleteTitle => 'اكتمل تسجيل الخروج';

  @override
  String get notificationCheckoutCompleteBody => 'تم تسجيل خروجك بنجاح.';

  @override
  String get notificationOrderQueuedTitle => 'تمت جدولة الطلب';

  @override
  String notificationOrderQueuedBody(Object orderNumber) {
    return 'تم حفظ الطلب $orderNumber. ستعمل المزامنة تلقائياً.';
  }

  @override
  String get notificationOrderPickupQueuedTitle => 'تمت جدولة استلام الطلب';

  @override
  String get notificationOrderDeliveryQueuedTitle => 'تمت جدولة تسليم الطلب';

  @override
  String notificationOrderSavedForSyncBody(Object orderNumber) {
    return 'تم حفظ الطلب $orderNumber للمزامنة.';
  }

  @override
  String get toastOrderQueuedLocalSync =>
      'تمت جدولة الطلب وحفظه محلياً. ستتم المزامنة خلال 5 دقائق.';

  @override
  String get toastPickupQueued =>
      'تمت جدولة الاستلام. ستعمل المزامنة تلقائياً خلال 5 دقائق كحد أقصى.';

  @override
  String get toastCancellationQueued =>
      'تمت جدولة الإلغاء. ستعمل المزامنة تلقائياً خلال 5 دقائق كحد أقصى.';

  @override
  String get toastDeliveryQueued =>
      'تمت جدولة التسليم. ستعمل المزامنة تلقائياً خلال 5 دقائق كحد أقصى.';
}
