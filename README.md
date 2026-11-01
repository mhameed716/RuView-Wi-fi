# RuView Wi-Fi · تطبيق أندرويد عربي للاستشعار عبر الواي فاي

<p align="center">
  <img src="docs/branding/app_icon_512.png" width="128" alt="RuView Wi-Fi" />
</p>

<p align="center">
  تطبيق Flutter جاهز للإنتاج، بواجهتين عربيتين (RTL) بالكامل، يتصل ببوابة
  <strong>RuView WiFi Sensing</strong> المحلية لمراقبة <strong>الحضور</strong>
  و<strong>الحركة</strong> و<strong>العلامات الحيوية</strong> — بدون أي كاميرات.
</p>

<p align="center">
  <code>Flutter 3.22+</code> · <code>MVVM</code> · <code>WebSocket + UDP</code> ·
  <code>Dark neon</code> · <code>بدون تبعيات ثقيلة</code>
</p>

---

## ما هذا؟

عميل أصلي (Native) لبوابة RuView الرسمية. البوابة تقرأ تشويش موجات الواي فاي
عبر CSI من عُقد ESP32 وتستنتج: هل يوجد شخص؟ يتحرّك أم ساكن؟ ما معدل تنفسه؟
هذا التطبيق يعرض ذلك على الهاتف في لوحة تحكم ولوحة رصد حية.

**لا كاميرات، لا سحابة، لا بيانات تغادر شبكتك المحلية.**

## الواجهتان

### 1. لوحة التحكم
- بطاقة إعدادات الاتصال: عنوان IP، المنفذ، مبدّل بروتوكول (WebSocket/UDP)،
  وخيارات متقدمة (رمز `RUVIEW_API_TOKEN` واتصال `wss`).
- زر اتصال/قطع مع مؤشر حي (متصل · جاري الاتصال · إعادة محاولة · غير متصل).
- شرائح مباشرة: الهدف، مدة الاتصال، معدل التحديث (Hz).
- أربع بطاقات ملخص: حالة النظام، العقد النشطة، الحضور الآن، جودة الإشارة.
- زر بارز للانتقال إلى لوحة الرصد.

### 2. لوحة الرصد
- **رادار حضور مكاني** مرسوم بـ `CustomPainter`: حلقات، مسح دوّار، نقط حياة
  من مواضع `persons[].position` الحقيقية، وتسمية عربية واضحة.
- **لوحة العلامات الحيوية**: عدّاد تنفس قوسي (نفس/دقيقة) بحالة عربية
  (طبيعي/سريع/بطيء)، شدة الحركة كمقياس متدرّج، درجة الثقة، ورسم مصغّر للتاريخ.
- **سجل الأنشطة والتنبيهات** في الأسفل: حضور، حركة، تنفس، إشارة، اتصال —
  بقواعد صريحة وحرّاس زمنية تمنع الإغراق.

## البدء السريع

```bash
# 1) تحضير المشروع
flutter create --platforms=android --org com.ruview .   # مرة واحدة (Gradle wrapper)
flutter pub get

# 2) تجربة فورية بلا أجهزة: بوابة محاكاة بنفس بروتوكول RuView الرسمي
node tools/mock_ruview_server.mjs --port 8080
#    ← معاينة الويب للتصميم:  http://localhost:8080/
#    ← للهاتف: أدخل IP جهاز الحاسوب والمنفذ 8080 ثم اضغط "اتصال"

# 3) تشغيل تطبيق الأندرويد
flutter run --release
```

دليل مفصّل (البناء، التوقيع، الاتصال ببوابة RuView الحقيقية، استكشاف الأخطاء):
[`docs/BUILD_AND_RUN.md`](docs/BUILD_AND_RUN.md)

## لقطات التصميم

المعاينة الحيّة في `preview/` نسخة ويب مطابقة للتصميم (نفس الألوان والنصوص
واللوحات والرادار) تعمل على نفس بوابة المحاكاة — تُفتح على
`http://localhost:8080/` بعد تشغيل الخادم.

## هيكل المشروع

```
RuView-Wi-fi/
├── lib/                     كود تطبيق Flutter (MVVM)
│   ├── core/                الثيم، الألوان، النصوص العربية، الأدوات، التنقل
│   ├── data/                Models · Services (WS/UDP/CSI) · Repository
│   └── presentation/        ViewModels · Screens · Widgets
├── test/                    اختبارات وحدة + ويدجت
├── android/                 مشروع أندرويد (Manifest، Gradle، الأيقونات)
├── preview/                 معاينة الويب للتصميم (HTML/CSS/JS بلا تبعيات)
├── tools/                   بوابة المحاكاة · سحب RuView الرسمي · مولّد الأيقونات
├── docs/                    البروتوكول · الهيكلية · البناء والتشغيل
└── vendor/ruview-official/  مقتطفات موثّقة من مشروع RuView الرسمي (MIT)
```

ملفات مهمة:

| الملف | الدور |
|---|---|
| [`lib/data/services/websocket_sensing_transport.dart`](lib/data/services/websocket_sensing_transport.dart) | عميل WebSocket: Bearer، إعادة اتصال أسّية، ping، رسائل أخطاء عربية |
| [`lib/data/services/udp_sensing_transport.dart`](lib/data/services/udp_sensing_transport.dart) | مستقبل UDP (JSON أو إطارات CSI) |
| [`lib/data/services/csi_analyzer.dart`](lib/data/services/csi_analyzer.dart) | فكّ إطار ESP32 (ADR-018) ومؤشرات محلية |
| [`lib/data/models/sensing_frame.dart`](lib/data/models/sensing_frame.dart) | نموذج `sensing_update` الرسمي + تسامح الحقول |
| [`lib/presentation/viewmodels/`](lib/presentation/viewmodels/) | `ConnectionViewModel` · `SensingViewModel` · قواعد الأحداث |
| [`lib/presentation/widgets/presence_radar.dart`](lib/presentation/widgets/presence_radar.dart) | الرادار الحي |
| [`tools/mock_ruview_server.mjs`](tools/mock_ruview_server.mjs) | بوابة محاكاة بلا تبعيات (WS + REST + معاينة) |

الهيكلية الكاملة وتدفّق البيانات: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## البروتوكول المدعوم

- `ws://<host>:8765/ws/sensing` (وأيضًا على منفذ HTTP `3000`، أو `3001`).
- رسائل `sensing_update` بكامل حقولها الرسمية (`classification`, `features`,
  `vital_signs`, `persons`, `signal_field`, `estimated_persons` …) مع دعم
  الأسماء البديلة بين إصدارات البوابات.
- مصادقة `Authorization: Bearer <token>` على ترقية WebSocket (ADR-272).
- UDP `5005`: إطارات CSI الثنائية (magic `0xC5110001`) أو JSON مبثوث.
- REST للتحقق السريع: `/health`, `/api/v1/info`, `/api/v1/nodes`,
  `/api/v1/sensing/latest`, `/api/v1/vital-signs`.

التفاصيل الكاملة مع الجداول: [`docs/PROTOCOL.md`](docs/PROTOCOL.md)

## مشروع RuView الرسمي

المرجع المعتمد هو [`ruvnet/RuView`](https://github.com/ruvnet/RuView) (رخصة MIT).
مقتطفات موثّقة (ADR-018/019/034/055/272 + `types.rs` + `LICENSE`) محفوظة في
[`vendor/ruview-official/`](vendor/ruview-official/PROVENANCE.md) على الالتزام
`5728b90`، وسحب المشروع كاملًا بأمر واحد:

```bash
./tools/fetch_official_ruview.sh          # → vendor/ruview-full (خارج Git)
```

## الاختبارات

```bash
flutter analyze
flutter test
python3 tools/check_dart_imports.py       # تدقيق استيرادات/أقواس سريع
```

يغطّي الاختبار تحليل الإطار الرسمي وكل الأسماء البديلة، تحقّق الإعدادات، فكّ
إطارات CSI الثنائية، قواعد الأحداث، تنعيم العلامات الحيوية، وواجهة لوحة
التحكم (النصوص العربية + RTL + التنقل).

## القيود وإخلاء المسؤولية

- معدل التنفس والنبض **تقديرات استنتاجية من CSI** وليست قياسات طبية معتمدة.
- مسار UDP المحلي (بدون بوابة) يستخدم مؤشرات مبسّطة في الهاتف؛ الدقة الكاملة
  تأتي من خادم RuView الرسمي عبر WebSocket.
- التطبيق مصمّم لشبكة محلية موثوقة (يسمح بـ `ws://` غير مشفّر لتلك الحالة).

## الترخيص

كود هذا التطبيق متاح بموجب رخصة MIT. مقتطفات RuView المحفوظة في
`vendor/ruview-official/` تخضع لرخصة MIT الأصلية وحقوق (c) 2024 rUv.
