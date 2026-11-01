# هيكلية تطبيق RuView Wi-Fi

تطبيق Flutter بنمط **MVVM** نظيف، بلا أي مكتبة إدارة حالة خارجية: الحالة في
`ChangeNotifier`، والحقن عبر `InheritedWidget` واحد، والبيانات عبر مستودع
(`repository`) يفصل الشبكة عن الواجهة.

```
┌─────────────────────────────────────────────────────────────────────┐
│  الواجهة (View)                                                      │
│  DashboardScreen ── ConnectionSettingsCard · SummaryTile · CTA       │
│  MonitorScreen   ── PresenceRadar · VitalsPanel · ActivityLogPanel   │
└───────────────▲──────────────────────────────┬──────────────────────┘
                │ ListenableBuilder            │ أوامر (connect/disconnect)
┌───────────────┴──────────────────────────────▼──────────────────────┐
│  ViewModels (ChangeNotifier)                                         │
│  ConnectionViewModel : نموذج الاتصال، الحالة، مدة الاتصال، معدل التحديث│
│  SensingViewModel    : الإطار الأخير، التنعيم، قواعد الأحداث، السجل   │
└───────────────▲──────────────────────────────┬──────────────────────┘
                │ Stream<SensingFrame>         │ connect(settings)
                │ Stream<ConnectionSnapshot>   │
┌───────────────┴──────────────────────────────▼──────────────────────┐
│  SensingRepository (SensingDataSource)                               │
│  يملك طبقة النقل، يحوّل JSON → SensingFrame، يبثّ الحالة               │
└───────────────▲──────────────────────────────────────────────────────┘
                │ Stream<TransportEvent>
┌───────────────┴──────────────────────────────────────────────────────┐
│  طبقة النقل (SensingTransport)                                       │
│  WebSocketSensingTransport  ← /ws/sensing + Bearer + backoff         │
│  UdpSensingTransport        ← ESP32 CSI (ADR-018) أو JSON مبثوث       │
│      └── CsiAnalyzer: فكّ الحزمة + مؤشرات محلية → sensing_update      │
└──────────────────────────────────────────────────────────────────────┘
```

## شجرة المشروع

```
lib/
├── main.dart                     نقطة الدخول (تثبيت الاتجاه + شريط الحالة)
├── app.dart                      MaterialApp + RTL + إنشاء الاعتماديات
├── core/
│   ├── l10n/ar_strings.dart      كل النصوص العربية في مكان واحد
│   ├── navigation/app_routes.dart انتقال سلس إلى لوحة الرصد
│   ├── theme/app_colors.dart     لوحة ألوان النيون الداكنة
│   ├── theme/app_theme.dart      الثيم + مساعد زخرفة الحقول
│   └── utils/                    num_utils · formatters (EMA، حلقات عينات)
├── data/
│   ├── models/                   SensingFrame · VitalSigns · NodeInfo · PersonDetection
│   │                             ClassificationInfo · SignalField · JsonRead
│   │                             ConnectionSettings · ConnectionStatus · ActivityEvent
│   ├── services/                 SensingTransport (عقد)
│   │                             websocket_sensing_transport.dart
│   │                             udp_sensing_transport.dart + csi_analyzer.dart
│   │                             settings_repository.dart (SharedPreferences)
│   └── repositories/
│       └── sensing_repository.dart
└── presentation/
    ├── app_scope.dart            InheritedWidget للاعتماديات
    ├── viewmodels/               connection · sensing · activity_rules
    ├── screens/                  dashboard_screen · monitor_screen
    └── widgets/                  neon_card · neon_button · status_pill · summary_tile
                                  connection_settings_card · presence_radar
                                  vitals_panel · activity_log_panel · sparkline
                                  app_background
```

## تدفّق البيانات

1. `ConnectionViewModel.connect()` يتحقق من النموذج (IP/المنفذ)، يحفظ الإعدادات
   في `SharedPreferences`، ثم ينادي `SensingRepository.connect(settings)`.
2. المستودع يختار النقل المناسب (`TransportKind.webSocket` أو `udp`) ويستمع
   إلى `TransportEvent`.
3. كل حزمة JSON تُحوّل عبر `SensingFrame.fromJson` (تسامح كامل مع الحقول
   الناقصة) ثم تُبثّ على `frames`.
4. `SensingViewModel` ينعّم التنفس (EMA بمعامل 0.22)، يحدّث حلقات الرسم،
   ويقيّم **قواعد الأحداث**، ثم `notifyListeners()`.
5. الواجهة تعيد البناء عبر `ListenableBuilder` فقط، والرسوم المتحركة الثقيلة
   (الرادار، العدّاد) تستخدم `AnimationController`/`TweenAnimationBuilder`
   مستقلًا لتجنّب إعادة بناء الشجرة كاملة.

## قواعد الأحداث (`activity_rules.dart`)

منطق نقي (`ActivityContext → ActivityEvent?`) قابل للاختبار بلا واجهة:

| القاعدة | الشرط | حرّاس زمني |
|---|---|---|
| `presenceRule` | تغيّر `presence` | — |
| `motionRule` | تغيّر `motion_level` بين متحرك/ساكن | 6 ث |
| `peopleCountRule` | تغيّر عدد الأشخاص أثناء الحضور | 10 ث |
| `breathingRule` | تغيّر تصنيف التنفس (طبيعي 12–20) | 25 ث |
| `signalStrengthRule` | عبور جودة الإشارة عتبة 0.35 | 45 ث |

بالإضافة إلى أحداث الاتصال/الأخطاء (متصل، انقطع، إعادة محاولة) وكشف توقف
البيانات (6 ثوانٍ صمت → «توقف وصول البيانات»).

## قرارات هندسية

| القرار | السبب |
|---|---|
| لا مكتبة إدارة حالة خارجية | `ChangeNotifier` + `InheritedWidget` كافيان ويقلّلان التبعيات إلى حدها الأدنى |
| `SharedPreferences` فقط كتبعية خارجية | تخزين الإعدادات بشكل موثوق على أندرويد/iOS |
| تجريد `SensingDataSource` | اختبار الـ ViewModels بلا شبكة أو مقابس |
| `dart:io` WebSocket مباشرة | دعم ترويسة `Authorization` على الترقية (مستحيل عبر حزم WebSocket للمتصفح) |
| تسامح كامل عند التحليل | البوابات تختلف؛ انهيار التحليل يعني فقدان الجلسة |
| مؤشرات محلية لـ UDP بصدق موثّق | تعمل بلا بوابة، لكنها ليست بديلًا عن خط المعالجة الرسمي |

## الاختبارات

```
test/
├── models/sensing_frame_test.dart        تحليل الإطار الرسمي وكل الأسماء البديلة
├── models/connection_settings_test.dart  التحقق، الروابط، الترويسات، JSON
├── services/csi_analyzer_test.dart       فكّ إطار ESP32 الثنائي + الحضور
├── presentation/activity_rules_test.dart قواعد الأحداث والحرّاس الزمنية
├── presentation/sensing_view_model_test.dart  التنعيم، الحضور، السجل
└── widget/dashboard_flow_test.dart       نصوص عربية + RTL + التنقل
```

```bash
flutter test
```

## نقاط التوسّع المقصودة

- **إضافة لغة**: تجميع النصوص في `ArStrings` يجعل إدخال `intl`/ARB لاحقًا سهلًا.
- **إضافة مسار REST**: أضف خدمة `RuViewApiService` تعيد استخدام
  `ConnectionSettings.authHeaders`.
- **دعم رسم مجال الإشارة**: `SensingFrame.signalField` مقروء بالفعل (شبكة + قيم)
  وينتظر فقط `CustomPainter` لخريطة حرارية.
- **إشعارات محلية**: `SensingViewModel.events` هو المكان الطبيعي لربط
  `flutter_local_notifications` عند حدث حرج (سقوط/انقطاع تنفس).
