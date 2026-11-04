import 'package:flutter/services.dart';

/// درجة أهمية التنبيه.
enum AlertSeverity { info, warning, critical }

/// تنبيه المستخدم عند حدث حرج (سقوط، تسلل، اضطراب تنفس).
///
/// ثلاث قنوات متتالية، كل واحدة مستقلة حتى لو فشلت الأخرى:
///  1. اهتزاز (HapticFeedback) — يعمل بلا أذونات إضافية.
///  2. صوت نظام (SystemSound).
///  3. إشعار نظام عبر قناة أندرويد أصلية `ruview/alerts` (بلا حزم خارجية).
///
/// التصميم «فاشل بأمان»: أي استثناء أو غياب للقناة (مثلًا على iOS أو في
/// الاختبارات) يُتجاهل ويبقى التنبيه المرئي داخل التطبيق هو الأساس.
class AlertDispatcher {
  AlertDispatcher({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'ruview/alerts';

  final MethodChannel _channel;

  /// طلب إذن الإشعارات (أندرويد 13+). آمن للاستدعاء المتكرر.
  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } catch (_) {
      // القناة غير متوفرة (منصّة أخرى) — لا شيء مطلوب.
    }
  }

  /// إصدار تنبيه كامل.
  Future<void> notify({
    required String title,
    required String body,
    AlertSeverity severity = AlertSeverity.warning,
  }) async {
    await _haptic(severity);
    await _sound(severity);
    await _systemNotification(title: title, body: body, severity: severity);
  }

  Future<void> _haptic(AlertSeverity severity) async {
    try {
      switch (severity) {
        case AlertSeverity.critical:
          await HapticFeedback.vibrate();
        case AlertSeverity.warning:
          await HapticFeedback.heavyImpact();
        case AlertSeverity.info:
          await HapticFeedback.selectionClick();
      }
    } catch (_) {
      // الاهتزاز غير مدعوم — تجاهل.
    }
  }

  Future<void> _sound(AlertSeverity severity) async {
    if (severity == AlertSeverity.info) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // الصوت غير مدعوم — تجاهل.
    }
  }

  Future<void> _systemNotification({
    required String title,
    required String body,
    required AlertSeverity severity,
  }) async {
    try {
      await _channel.invokeMethod<bool>('notify', <String, dynamic>{
        'title': title,
        'body': body,
        'critical': severity == AlertSeverity.critical,
      });
    } catch (_) {
      // لا قناة إشعارات على هذه المنصّة — التنبيه داخل التطبيق يكفي.
    }
  }
}
