/// جميع نصوص التطبيق بالعربية في مكان واحد.
///
/// التطبيق أحادي اللغة (العربية) واتجاه RTL بالكامل، لذلك لا نستخدم نظام
/// الترجمة الكامل (ARB) لتفادي التعقيد، لكن تجميع النصوص هنا يجعل التعديل
/// والمراجعة اللغوية سهلة، ويسمح بإضافة لغة ثانية لاحقًا دون البحث في الواجهات.
abstract final class ArStrings {
  // ── عام ────────────────────────────────────────────────────────────────
  static const String appName = 'RuView Wi-Fi';
  static const String appTagline = 'استشعار مكاني عبر الواي فاي — بدون كاميرات';
  static const String dashboardTitle = 'لوحة التحكم';
  static const String monitorTitle = 'لوحة الرصد';
  static const String back = 'رجوع';
  static const String retry = 'إعادة المحاولة';
  static const String cancel = 'إلغاء';
  static const String save = 'حفظ';
  static const String close = 'إغلاق';

  // ── إعدادات الاتصال ───────────────────────────────────────────────────
  static const String connectionSettings = 'إعدادات الاتصال';
  static const String connectionSettingsHint =
      'أدخل عنوان بوابة RuView على شبكتك المحلية';
  static const String serverIp = 'عنوان IP للخادم';
  static const String serverIpHint = 'مثال: 192.168.1.50';
  static const String port = 'المنفذ';
  static const String portHint = 'مثال: 8765';
  static const String transport = 'بروتوكول النقل';
  static const String transportWebSocket = 'WebSocket';
  static const String transportUdp = 'UDP';
  static const String advancedOptions = 'خيارات متقدمة';
  static const String authToken = 'رمز الوصول (اختياري)';
  static const String authTokenHint = 'RUVIEW_API_TOKEN إن كان مُفعّلًا';
  static const String useSecureConnection = 'اتصال مشفّر (wss)';
  static const String connect = 'اتصال';
  static const String disconnect = 'قطع الاتصال';
  static const String reconnect = 'إعادة الاتصال';
  static const String invalidHost = 'أدخل عنوان IP أو اسم مضيف صالحًا';
  static const String invalidPort = 'أدخل رقم منفذ بين 1 و 65535';
  static const String settingsSaved = 'تم حفظ إعدادات الاتصال';

  // ── حالة الاتصال ──────────────────────────────────────────────────────
  static const String statusConnected = 'متصل';
  static const String statusConnecting = 'جاري الاتصال...';
  static const String statusReconnecting = 'إعادة محاولة الاتصال...';
  static const String statusDisconnected = 'غير متصل';
  static const String statusError = 'فشل الاتصال';
  static const String statusUdpListening = 'يستمع لمنفذ UDP';
  static const String dataStale = 'لا تصل بيانات حديثة';
  static const String noDataYet = 'بانتظار أول حزمة بيانات';

  // ── بطاقات الملخص ─────────────────────────────────────────────────────
  static const String systemStatus = 'حالة النظام';
  static const String activeNodes = 'العقد النشطة';
  static const String presenceNow = 'الحضور الآن';
  static const String signalQuality = 'جودة الإشارة';
  static const String openMonitor = 'الانتقال إلى لوحة الرصد';
  static const String openMonitorHint = 'رادار الحضور والعلامات الحيوية';
  static const String node = 'عقدة';
  static const String nodesUnit = 'عقدة نشطة';
  static const String personDetected = 'شخص مرصود';
  static const String noPerson = 'لا يوجد أشخاص';
  static const String uptime = 'مدة الاتصال';
  static const String frameRate = 'معدل التحديث';
  static const String source = 'المصدر';

  // ── لوحة الرصد ────────────────────────────────────────────────────────
  static const String presenceRadar = 'رادار الحضور المكاني';
  static const String radarActive = 'تم رصد شخص في المنطقة';
  static const String radarIdle = 'المنطقة فارغة';
  static const String radarNoSignal = 'لا توجد بيانات للرصد';
  static const String radarHint = 'الموجات تُبيّن الحركة والتنفس داخل النطاق';
  static const String vitalsPanel = 'العلامات الحيوية';
  static const String breathingRate = 'معدل التنفس';
  static const String motionIntensity = 'شدة الحركة';
  static const String heartRate = 'معدل النبض التقديري';
  static const String confidence = 'درجة الثقة';
  static const String normal = 'طبيعي';
  static const String low = 'منخفض';
  static const String high = 'مرتفع';
  static const String still = 'ساكن';
  static const String moving = 'متحرك';
  static const String absent = 'غائب';
  static const String activityLog = 'سجل الأنشطة والتنبيهات';
  static const String noEvents = 'لا توجد أحداث بعد — ابدأ الاتصال لعرض السجل';
  static const String clearLog = 'مسح السجل';
  static const String breathsPerMinute = 'نفس/دقيقة';
  static const String percent = '%';

  // ── أحداث السجل ───────────────────────────────────────────────────────
  static const String eventConnected = 'تم الاتصال بالبوابة';
  static const String eventDisconnected = 'تم قطع الاتصال';
  static const String eventConnectionError = 'تعذّر الاتصال بالبوابة';
  static const String eventReconnecting = 'إعادة محاولة الاتصال';
  static const String eventStable = 'الاتصال مستقر';
  static const String eventPresenceDetected = 'تم رصد حضور في المنطقة';
  static const String eventPresenceLost = 'غادر الشخص المنطقة';
  static const String eventMotionDetected = 'تم رصد حركة';
  static const String eventMotionStopped = 'توقفت الحركة';
  static const String eventBreathingNormal = 'تنفس طبيعي';
  static const String eventBreathingFast = 'تنفس سريع';
  static const String eventBreathingSlow = 'تنفس بطيء';
  static const String eventVitalsLost = 'انقطاع قياس العلامات الحيوية';
  static const String eventWeakSignal = 'إشارة ضعيفة';
  static const String eventSignalRecovered = 'استعادة قوة الإشارة';
  static const String eventDataStale = 'توقف وصول البيانات';
  static const String eventDataResumed = 'استؤنف وصول البيانات';
  static const String eventPeopleCountChanged = 'تغيّر عدد الأشخاص';
  static const String eventFirstFrame = 'بدأ استقبال بيانات الاستشعار';

  // ── رسائل ─────────────────────────────────────────────────────────────
  static const String simulationNotice =
      'لم يتم الاتصال بأي بوابة. البطاقات تعرض آخر قراءة معروفة.';
  static const String connectionErrorHint =
      'تأكد من عنوان IP والمنفذ، وأن الهاتف متصل بنفس شبكة البوابة.';
  static const String justNow = 'الآن';
  static const String secondsAgo = 'ث';
  static const String minutesAgo = 'د';
  static const String hoursAgo = 'س';
}
