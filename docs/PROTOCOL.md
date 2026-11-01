# بروتوكول RuView — المرجع المستخدم في التطبيق

هذا الملف يوثّق **العقد الشبكي الرسمي** بين بوابة RuView (المشروع الأصلي
`ruvnet/RuView`) وأي عميل خارجي، وهو بالضبط ما يطبّقه تطبيق RuView Wi-Fi.

> المصدر: نسخة مثبّتة من المستودع الرسمي محفوظة في
> [`vendor/ruview-official/`](../vendor/ruview-official/) مع بصمة الالتزام
> في [`PROVENANCE.md`](../vendor/ruview-official/PROVENANCE.md).
> المراجع الأساسية: `ADR-019` (صيغة `sensing_update`)، `ADR-018` (إطار ESP32
> الثنائي)، `ADR-034` (تطبيق موبايل)، `ADR-055` (خادم الاستشعار)، `ADR-272`
> (مصادقة WebSocket)، و`types.rs` (بنية الرسائل في Rust).

---

## 1. المنافذ والمسارات

| الغرض | العنوان | ملاحظة |
|---|---|---|
| بث الاستشعار الحي | `ws://<host>:8765/ws/sensing` | المنفذ الافتراضي في كثير من النشرات |
| نفس البث على منفذ HTTP | `ws://<host>:3000/ws/sensing` | موصى به — منفذ واحد فقط |
| منفذ WS مخصّص | `ws://<host>:3001/ws/sensing` | توافق خلفي |
| بث الوضعية | `ws://<host>:8765/ws/pose` | اختياري |
| REST — الحالة | `GET /health`، `GET /health/ready`، `GET /api/v1/info` | |
| REST — آخر إطار | `GET /api/v1/sensing/latest` | |
| REST — العلامات الحيوية | `GET /api/v1/vital-signs` | |
| REST — العقد | `GET /api/v1/nodes` | |
| UDP — إطارات CSI | `udp://<host>:5005` | من عُقد ESP32 مباشرة |

التطبيق يضبط المنفذ افتراضيًا على `8765` لـ WebSocket و`5005` لـ UDP، وكلاهما
قابل للتعديل من الواجهة.

---

## 2. رسالة `sensing_update` (JSON)

البنية كما في `SensingUpdate` داخل
`vendor/ruview-official/crates/wifi-densepose-sensing-server/src/types.rs`:

```json
{
  "type": "sensing_update",
  "timestamp": 1793562081.919,
  "source": "esp32",
  "tick": 1024,
  "nodes": [
    {
      "node_id": 1,
      "rssi_dbm": -39.0,
      "position": [2.0, 0.0, 1.5],
      "amplitude": [12.1, 11.8, 12.4],
      "subcarrier_count": 3
    }
  ],
  "features": {
    "mean_rssi": -39.0,
    "variance": 2.34,
    "motion_band_power": 0.45,
    "breathing_band_power": 0.21,
    "dominant_freq_hz": 0.26,
    "change_points": 2,
    "spectral_power": 1.7
  },
  "classification": {
    "motion_level": "present_moving",
    "presence": true,
    "confidence": 0.87
  },
  "signal_field": {
    "grid_size": [20, 1, 20],
    "values": [0.02, 0.71, 0.03]
  },
  "vital_signs": {
    "breathing_rate_bpm": 15.2,
    "heart_rate_bpm": 68.0,
    "breathing_confidence": 0.72,
    "heartbeat_confidence": 0.61,
    "signal_quality": 0.8
  },
  "estimated_persons": 1,
  "signal_quality_score": 0.8,
  "quality_verdict": "good",
  "posture": "sitting",
  "persons": [
    {
      "id": 1,
      "confidence": 0.9,
      "zone": "zone_1",
      "position": [2.4, 0.0, 3.1],
      "motion_score": 55.0,
      "pose": "sitting",
      "bbox": { "x": 0.1, "y": 0.2, "width": 0.3, "height": 0.5 },
      "keypoints": [{ "name": "nose", "x": 0.5, "y": 0.3, "z": 0.0, "confidence": 0.91 }]
    }
  ]
}
```

### الحقول وقيودها

| الحقل | النوع | الدلالة |
|---|---|---|
| `timestamp` | `f64` | ثوانٍ عشرية منذ Unix epoch. بعض البوابات ترسلها بالمللي ثانية — التطبيق يكتشف ذلك تلقائيًا. |
| `tick` | `u64` | عدّاد إطارات الخادم (يزيد واحدًا لكل بث). |
| `source` | `string` | `esp32` / `wifi:<ssid>` / `simulated` / `mediatek` … |
| `classification.motion_level` | `string` | `absent`، `present_still`، `present_moving`، (وقد يظهر `active`). |
| `classification.presence` | `bool` | يُشتق في الخادم الرسمي من `motion_level != absent`. |
| `classification.confidence` | `0..1` | ثقة التصنيف. |
| `features.motion_band_power` | `float` | طاقة نطاق الحركة — يُشتق منها مؤشر شدة الحركة. |
| `signal_field.grid_size` | `[x, y, z]` | شبكة مجال الإشارة (عادة `20×1×20` على مستوى الأرضية). |
| `vital_signs.breathing_rate_bpm` | `float` | معدل التنفس (نفس/دقيقة). |
| `vital_signs.heart_rate_bpm` | `float` | نبض تقديري (ليس قياسًا طبيًا). |
| `persons[].position` | `[x, y, z]` | موضع على مستوى الأرضية بالأمتار (`y = 0`). |
| `persons[].motion_score` | `0..100` | شدة حركة الشخص. |
| `posture` | `string?` | وضعية الجسم على مستوى الإطار: `standing`، `sitting`، `lying`، `walking`، `bending`، `fallen`. اختيارية. |
| `persons[].pose` | `string?` | وضعية الشخص نفسه (تسبق الاستنتاج المحلي من المفاصل). |
| `persons[].keypoints[]` | `array?` | مفاصل 17 نقطة COCO مع `name` و`x`/`y` (مطبّعة 0..1) و`z` و`confidence`. اختيارية. |

اختلافات أسماء يجب دعمها (موجودة في بوابات/إصدارات مختلفة):

- معدل التنفس: `breathing_rate_bpm` أو `breathing_bpm`
- النبض: `heart_rate_bpm` أو `hr_proxy_bpm`
- ثقة النبض: `heartbeat_confidence` أو `heart_confidence`
- الحضور: `presence` أو `is_present`

التطبيق يقرأ كل هذه الأسماء عبر طبقة [`JsonRead`](../lib/data/models/json_read.dart)
ويتحمّل الحقول الناقصة أو القيم النصية دون انهيار.

### الوضعية والمفاصل (حقول اختيارية)

- `posture` و`persons[].pose` يُطبّعان عبر `PostureKind.fromWire` مع دعم
  مرادفات مثل `upright`، `seated`، `on_bed`، `fall_detected`، `on_floor`.
- أسماء المفاصل المدعومة: `nose`، `left/right_shoulder`، `left/right_hip`،
  `left/right_knee` (وغيرها تُتجاهل). إن غابت الأسماء يُفترض ترتيب COCO.
- ترتيب أولوية تقدير الوضعية في التطبيق:
  1. `posture` على مستوى الإطار (ثقة الخادم).
  2. `persons[].pose`.
  3. هندسة المفاصل (تقريبي): جسم أفقي ⇒ استلقاء، رأس تحت الكتفين ⇒ انحناء،
     حوض بمستوى الركبة ⇒ جلوس، امتداد رأسي كبير ⇒ وقوف.
  4. `classification.motion_level` كملاذ أخير (متحرك ⇒ مشي).
- التطبيق يعمل بلا هذه الحقول، ولا يفترض وجودها.

### معدل البث

الخادم الرسمي يبثّ حسب `--tick-ms` (شائع: 100–500 مللي ثانية). التطبيق يعرض
`معدل التحديث` بالهرتز محسوبًا من فواصل الإطارات الفعلية.

---

## 3. المصادقة (ADR-272)

- عند تشغيل الخادم بـ `RUVIEW_API_TOKEN=<token>` تصبح كل المسارات محمية.
- **العملاء الأصليون (مثل تطبيق أندرويد) يرسلون ترويسة عادية على ترقية
  WebSocket:**

  ```http
  GET /ws/sensing HTTP/1.1
  Upgrade: websocket
  Authorization: Bearer <token>
  ```

  وهذا ما يفعله `WebSocketSensingTransport` في التطبيق.
- المتصفحات لا تستطيع إرسال ترويسات على الترقية، لذلك تستخدم تذكرة لمرة
  واحدة: `POST /api/v1/ws-ticket` ثم `?ticket=<value>`.

---

## 4. إطارات CSI الثنائية عبر UDP (ADR-018)

عندما يبثّ ESP32 حزم CSI خامًا إلى المنفذ `5005`:

| الإزاحة | الحجم | الحقل |
|---|---|---|
| 0 | 4 | `magic = 0xC5110001` (little-endian) |
| 4 | 1 | `node_id` |
| 5 | 1 | `antennas` |
| 6 | 2 | `n_subcarriers` |
| 8 | 4 | `freq_mhz` |
| 12 | 4 | `sequence` |
| 16 | 1 | `rssi` (int8) |
| 17 | 1 | `noise_floor` (int8) |
| 18 | 1 | `ppdu_type` (ADR-110) |
| 19 | 1 | محجوز |
| 20 | `n×2` | أزواج I/Q (int8) لكل ناقل فرعي |

التطبيق يفكّ هذه الحزم في
[`csi_analyzer.dart`](../lib/data/services/csi_analyzer.dart)، يحسب السعة
`sqrt(I²+Q²)`، ثم يستخرج مؤشرات محلية (طاقة الحركة، التباين، تقدير تنفس) ويصيغها
بصيغة `sensing_update` نفسها كي تعمل بقية الطبقات دون تغيير.

> **تنبيه صدق هندسي:** هذا المسار المحلي **تقديري** وليس بديلًا عن خط
> المعالجة الرسمي (ADR-031) الذي يحسب `signal_field` وبصمة الوضعية على الخادم.
> للحصول على أرقام معتمدة، استخدم WebSocket مع خادم RuView الرسمي.

---

## 5. سلوك الاتصال المتوقّع من العميل

1. الاتصال بالمسار `/ws/sensing`، وقراءة رسائل JSON نصية.
2. تجاهل الرسائل التي ليست من نوع `sensing_update` (رسائل إدارية/ترحيب).
3. الخادم يرسل `Ping` كل 30 ثانية (ADR-044/045) — على العميل الردّ بـ`Pong`.
   `dart:io` يفعل ذلك تلقائيًا عند ضبط `WebSocket.pingInterval`.
4. عند الانقطاع: إعادة اتصال بتباعد أسّي (1، 2، 4، 8، 15، 30 ث) مع تشويش.
5. معدل إطارات منخفض لا يعني انقطاعًا؛ يُعرض «لا تصل بيانات حديثة» بعد 6–8
   ثوانٍ من الصمت.
