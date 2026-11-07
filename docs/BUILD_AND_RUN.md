# البناء والتشغيل

## المتطلبات

| الأداة | الإصدار |
|---|---|
| Flutter | 3.22 أو أحدث (Dart 3.4+) |
| Android SDK | API 34 (compileSdk) مع minSdk 23 |
| جهاز/محاكي | أندرويد 6.0+ — **الجهاز الحقيقي أفضل** لاختبار UDP |
| Node.js | 18+ (لبوابة المحاكاة والمعاينة فقط) |

## 1) تحضير المشروع

```bash
cd RuView-Wi-fi

# إن كان مجلّد android/gradle/gradle-wrapper.jar مفقودًا (ملف ثنائي غير مضمّن):
flutter create --platforms=android --org com.ruview .

flutter pub get
```

> `flutter create .` آمن على المشروع القائم: يعيد إنشاء ملفات المنصّة الناقصة
> فقط (Gradle wrapper، أيقونات مفقودة…) ولا يلمس `lib/` أو `pubspec.yaml`.

## 2) تشغيل التطبيق

```bash
flutter devices            # تأكد من رؤية الجهاز
flutter run --release      # أو flutter run للتصحيح
```

## 3) تشغيل بوابة محاكاة (اختياري لكن مفيد)

قبل توفّر أجهزة ESP32، شغّل بوابة محاكاة تُقدّم نفس بروتوكول RuView:

```bash
node tools/mock_ruview_server.mjs --port 8080
```

مخرجاتها:

```
المعاينة : http://localhost:8080/            ← معاينة ويب للتصميم
WebSocket: ws://0.0.0.0:8080/ws/sensing      ← نفس بروتوكول الخادم الرسمي
REST     : http://localhost:8080/api/v1/sensing/latest
```

ثم من التطبيق:

- **IP**: عنوان جهاز الحاسوب في الشبكة المحلية (مثال `192.168.1.20`)
- **المنفذ**: `8080`
- **النقل**: `WebSocket`
- اضغط **اتصال** → تتحرك بطاقات الملخص والرادار فورًا.

اختبار المصادقة (ADR-272):

```bash
node tools/mock_ruview_server.mjs --port 8080 --token my-secret
# أدخل my-secret في "خيارات متقدمة → رمز الوصول"
```

## 4) الاتصال ببوابة RuView الرسمية

```bash
# مثال من دليل المشروع الرسمي (خادم استشعار Rust)
./target/release/sensing-server --source esp32 --udp-port 5005 \
    --http-port 3000 --ws-port 3001 --tick-ms 200
```

في التطبيق:

| الحالة | IP | المنفذ | النقل |
|---|---|---|---|
| بث على منفذ HTTP | IP الجهاز | `3000` | WebSocket |
| بث على منفذ WS المخصّص | IP الجهاز | `3001` أو `8765` | WebSocket |
| حزم CSI خام من ESP32 | IP الجهاز/البوابة | `5005` | UDP |
| خادم مع رمز وصول | — | — | WebSocket + رمز في «خيارات متقدمة» |

> على جهاز أندرويد حقيقي، لا تستخدم `localhost`: الهاتف ليس الخادم. استخدم
> عنوان IP للحاسوب/البوابة داخل نفس شبكة الواي فاي.

## 5) بناء ملف APK للإصدار

```bash
flutter build apk --release --split-per-abi
# المخرجات: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### البناء التلقائي على GitHub Actions

لا حاجة لـ Flutter محليًا: خط الأنابيب `.github/workflows/ci.yml` يبني
`app-release.apk` (حزمة شاملة لكل المعماريات) بعد نجاح التحليل والاختبارات،
ويرفعه كأثر (Artifact) باسم `ruview-wifi-apk` في تبويب **Actions**.
وسم (`v1.2.0` مثلًا) يُنشئ صفحة إصدار GitHub ويُرفق بها ملف APK تلقائيًا.

### توقيع إصدار حقيقي

1. أنشئ مفتاحًا:

   ```bash
   keytool -genkey -v -keystore ~/ruview-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias ruview
   ```

2. أنشئ `android/key.properties`:

   ```properties
   storePassword=***
   keyPassword=***
   keyAlias=ruview
   storeFile=/absolute/path/ruview-release.jks
   ```

3. استبدل سطر التوقيع في `android/app/build.gradle`:

   ```gradle
   def keystoreProperties = new Properties()
   def keystoreFile = rootProject.file("key.properties")
   if (keystoreFile.exists()) {
       keystoreProperties.load(new FileInputStream(keystoreFile))
   }

   android {
       signingConfigs {
           release {
               keyAlias keystoreProperties["keyAlias"]
               keyPassword keystoreProperties["keyPassword"]
               storeFile file(keystoreProperties["storeFile"])
               storePassword keystoreProperties["storePassword"]
           }
       }
       buildTypes {
           release { signingConfig signingConfigs.release }
       }
   }
   ```

## 6) الاختبارات والتحقق

```bash
flutter analyze          # محلّل Dart
flutter test             # اختبارات الوحدة والويدجت
python3 tools/check_dart_imports.py   # تدقيق بنية سريع (استيرادات/أقواس)
node --check preview/app.js && node --check tools/mock_ruview_server.mjs
```

## 7) معاينة الواجهة في المتصفح

```bash
node tools/mock_ruview_server.mjs --port 8080
# ثم افتح http://localhost:8080/
```

المعاينة نسخة ويب مطابقة للتصميم (نفس الألوان والنصوص واللوحات)، تتصل فعليًا
بـ WebSocket، وتتحوّل تلقائيًا إلى محاكاة محلية إن تعذّر الاتصال.

---

## 8) أذونات الرصد المتقدم

| الإذن | الغرض | متى يُطلب |
|---|---|---|
| `VIBRATE` | اهتزاز الهاتف عند السقوط/التسلل/اضطراب النفس | مُعلن في `AndroidManifest.xml` |
| `POST_NOTIFICATIONS` | إشعار نظام لتنبيهات الأمان الحرجة | يُطلب عند أول تشغيل (أندرويد 13+) |
| `ACTION_DIAL` | فتح لوحة الهاتف على رقم الطوارئ | لا يحتاج إذنًا — لا يتصل تلقائيًا |

- إن رفض المستخدم إذن الإشعارات، يبقى التنبيه داخل التطبيق (لافتة حمراء +
  اهتزاز) هو الأساس، ولا يتعطّل شيء.
- رقم الطوارئ الافتراضي **997** وقابل للتعديل من بطاقة الحراسة في لوحة التحكم.
- متجهات بصمة المشية تُحفظ في `SharedPreferences` (أرقام ميزات فقط، بلا
  صور أو تسجيل صوتي).

## استكشاف الأخطاء

| العرض | السبب المرجّح | الحل |
|---|---|---|
| «انتهت مهلة الاتصال (8 ث)» | IP/منفذ خطأ أو جدار حماية | تحقّق من `ping` للبوابة وأن المنفذ مفتوح |
| «رفض الخادم الاتصال: رمز الوصول غير صحيح (401)» | الخادم محمي برمز | ضع `RUVIEW_API_TOKEN` في خيارات متقدمة |
| «المسار /ws/sensing غير موجود (404)» | منفذ HTTP لا يقدّم WebSocket | جرّب منفذ WS المخصّص (8765/3001) |
| «المنفذ 5005 مستخدم بالفعل» | تطبيق آخر يحتجز المنفذ | أغلق التطبيق الآخر أو غيّر المنفذ |
| الاتصال متصل لكن لا بيانات | لا يوجد بث (العقد متوقفة) | راقب `معدل التحديث`، وشغّل بوابة المحاكاة للمقارنة |
| لا تصل حزم UDP من ESP32 | بثّ/جدار حماية/بث متعدد | تأكّد أن العقدة ترسل إلى IP الهاتف، ومنح إذن `CHANGE_WIFI_MULTICAST_STATE` (معلن مسبقًا) |
| شاشة فارغة/بيضاء عند الإقلاع | وميض الثيم الافتراضي | مضبوط مسبقًا عبر `launch_background` الداكن |

### ملاحظات أمنية

- التطبيق يسمح بـ `cleartext` (ws/http) لأن البوابة محلية؛ لا تستخدمه خارج
  شبكتك الموثوقة. عند النشر عبر شبكة غير موثوقة، فعّل `wss` (خيار متقدم)
  واضبط شهادة صالحة على الخادم.
- الرمز يُحفظ في `SharedPreferences` غير المشفّرة. للإصدارات الحساسة انقل
  التخزين إلى `flutter_secure_storage`.
