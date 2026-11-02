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
│   │                             lan_scanner.dart (اكتشاف/اتصال تلقائي)
│   │                             network_preferences_repository.dart
│   └── repositories/
│       └── sensing_repository.dart
└── presentation/
    ├── app_scope.dart            InheritedWidget للاعتماديات
    ├── viewmodels/               connection · sensing · activity_rules
    ├── screens/                  dashboard_screen · monitor_screen
    └── widgets/                  neon_card · neon_button · status_pill · summary_tile
                                  connection_settings_card · presence_radar
                                  vitals_panel · activity_log_panel · sparkline
                                  posture_status_card · skeleton_view
                                  emergency_banner · security_mode_card
                                  sleep_vitals_panel · monitoring_dialogs
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
5. بعد القواعد الأساسية يمرّ الإطار على `SafetyMonitor.ingest` الذي يشغّل
   خمسة محرّكات في `lib/domain/monitoring/` ويعيد `List<SafetySignal>`
   (وضعية، سقوط، تسلل، مشية، نوم/تنفس). كل إشارة تُترجم إلى `ActivityEvent`،
   والإشارات الحرجة (`fall`/`intrusion`/`apnea`) تُرسَل أيضًا إلى
   `AlertDispatcher` (اهتزاز + صوت + إشعار نظام).
6. الواجهة تعيد البناء عبر `ListenableBuilder` فقط، والرسوم المتحركة الثقيلة
   (الرادار، العدّاد، الهيكل العظمي) تستخدم `CustomPainter`/
   `AnimationController` مستقلًا لتجنّب إعادة بناء الشجرة كاملة.

## الاكتشاف التلقائي (`lib/data/services/lan_scanner.dart`)

| المكوّن | الدور |
|---|---|
| `NetworkContext` | يقرأ كل عناوين IPv4 الخاصة (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`) ويبني بادئات `/24` لكل واجهة + بصمة مستقرة للشبكة |
| `LanScanner.hostsFor` | ترتيب الأهداف: محفوظ → بوابة كل شبكة (`.1`) → عنوان الجهاز → `.254/.2/.100` → `ruview.local` → `127.0.0.1` → بقية `/24` |
| `LanScanner.probe` | TCP + `GET /health` (مهلة 220 ms، قراءة 450 ms) ثم مطابقة بصمة RuView في جسم الرد |
| `LanScanner.broadcastProbe` | بثّ UDP على 5005 (`RUVIEW_DISCOVERY_V1`) إلى `255.255.255.255` وكل `<بادئة>.255`، وجمع ردود البوابات |
| `LanCandidate.score` | ‎+100 RuView، ‎+45 محفوظ، ‎+18 بوابة، ‎+10 WS، ‎+6 منفذ 8765، وخصم على الاستجابة |
| `NetworkWatcher` | كل 5 ثوانٍ يقارن البصمة؛ عند تغيّر الشبكة يقطع الاتصال ويعيد الاكتشاف كاملًا |
| `ConnectionViewModel` | `runAutoConnect` → مسح → تجربة أفضل 4 مرشّحين → **لا يعتمد الاتصال إلا بعد وصول إطارات فعلية** |

القرارات المقصودة: المسح العميق افتراضي عند الارتباط بالشبكة (لأن الخادم قد
يكون على حاسوب داخل الشبكة لا على البوابة)، والتوقّف المبكر عند أول خادم
مؤكَّد، وعدم انتظار مهلة البثّ إن حسم فحص TCP الهوية.

المختبر: `tools/router_sim.mjs` (+ `tools/router_lab.mjs`) يبني راوترات
ونقاط اتصال هاتف افتراضية ويشغّل نسخة مطابقة للخوارزمية في Node، لأن بيئة
التطوير لا تملك واجهة LAN حقيقية.

## طبقة الرصد المتقدم (`lib/domain/monitoring/`)

| المحرّك | القاعدة | الحالة المخزّنة |
|---|---|---|
| `PostureEstimator` | خادم ← شخص ← مفاصل ← حركة | — (نقي) |
| `FallDetector` | وقوف/مشي ← أرض خلال ≤2 ث + حركة ≥0.55؛ تهدئة 15 ث | آخر وضعية مرتفعة |
| `IntrusionDetector` | مفعّل + مرور 20 ث + حركة ≥0.22؛ تهدئة 30 ث | وقت التسليح/آخر تنبيه |
| `GaitAnalyzer` | نافذة 12 ث من إطارات المشي، ≥15 عينة، تشابه جيب تمام | نافذة العينات |
| `SleepMonitor` | استلقاء/سكون + تنفس؛ انقطاع 25 ث = اضطراب | جلسة + معدلات + جودة |

`SafetyMonitor` هو المنسّق: يملك المحرّكات، يمنع وميض مطابقة المشية
(`requiredGaitStreak`)، ويحتفظ بـ `SafetyState` غير القابل للتغيير الذي يعرضه
`SensingViewModel` للواجهة (`posture`, `fallAlert`, `intrusionArmed`, `sleep`…).

**الاستمرارية**: `MonitoringSettingsRepository` يحفظ وضع الحراسة، رقم
الطوارئ، ومتجهات ميزات المشية (JSON) في `SharedPreferences` فقط — لا صور ولا
تسجيلات.

**القنوات الأصلية (أندرويد)**: قناتان بسيطتان في `MainActivity.kt` بدل حزم
ثقيلة: `ruview/alerts` (إشعار نظام + إذن أندرويد 13) و`ruview/emergency`
(`ACTION_DIAL`). كل استدعاء «فاشل بأمان»: عند غياب القناة يُكتفى بالتنبيه
المرئي/الاهتزاز أو بنسخ الرقم.

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
├── domain/posture_estimator_test.dart    أولوية مصادر الوضعية + المفاصل
├── domain/fall_detector_test.dart        نافذة السقوط + العتبات + التهدئة
├── domain/intrusion_detector_test.dart   التسليح + التهدئة + المنطقة
├── domain/gait_analyzer_test.dart        النافذة + المتجه + التشابه
├── domain/sleep_monitor_test.dart        النوم العميق + انقطاع النفس + الجودة
├── domain/safety_monitor_test.dart       دمج المحرّكات + الإشارات
├── services/monitoring_settings_repository_test.dart  الحفظ والقراءة
├── widget/monitoring_widgets_test.dart   بطاقات الوضعية/النوم/الحراسة/الطوارئ
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
- **إشعارات محلية غنية**: القناة الأصلية `ruview/alerts` تكفي للإشعارات
  الحرجة؛ عند الحاجة إلى إجراءات/صور يمكن استبدالها بـ
  `flutter_local_notifications` دون تغيير الواجهة.
- **تعريف بيومتري أدق**: استبدال `GaitAnalyzer` بنموذج تعلّم آلي على متجهات
  CSI متعددة العقد مع الحفاظ على واجهة `GaitFeatureVector` نفسها.
