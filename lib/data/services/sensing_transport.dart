import '../models/connection_settings.dart';
import '../models/connection_status.dart';

/// عقد موحّد لطبقة النقل (WebSocket أو UDP).
///
/// طبقة النقل لا تعرف شيئًا عن الواجهة: تُصدر [TransportEvent] فقط، وأحداث
/// الإطارات تكون خرائط JSON بصيغة `sensing_update` الرسمية، ثم يحوّلها
/// المستودع إلى نماذج مجال (`SensingFrame`).
abstract class SensingTransport {
  /// أحداث متعددة المشتركين: الاتصال، الانقطاع، الإطارات، الأخطاء.
  Stream<TransportEvent> get events;

  /// هل هناك اتصال/استماع نشط؟
  bool get isActive;

  /// فتح الاتصال. يُطلق استثناء فقط عند فشل فوري في التهيئة.
  Future<void> connect(ConnectionSettings settings);

  /// إغلاق واعٍ لاتجاه المستخدم (يمنع إعادة الاتصال التلقائي).
  Future<void> disconnect();

  /// تحرير الموارد نهائيًا.
  Future<void> dispose();
}
