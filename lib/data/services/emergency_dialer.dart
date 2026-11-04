import 'package:flutter/services.dart';

/// نتيجة محاولة الاتصال بالطوارئ.
enum DialOutcome {
  /// فُتح تطبيق الهاتف على الرقم.
  dialerOpened,

  /// لم تتوفر قناة الاتصال (مثلًا في الاختبارات) — تم نسخ الرقم.
  copiedToClipboard,

  /// رقم غير صالح.
  invalidNumber,
}

/// فتح تطبيق الهاتف على رقم الطوارئ.
///
/// يستخدم قناة أندرويد أصلية `ruview/emergency` تُطلق `ACTION_DIAL` (فتح لوحة
/// الاتصال مع الرقم جاهزًا) — أي أنها لا تتصل تلقائيًا، وهو السلوك الآمن
/// والمطلوب لتفادي الاتصالات الكاذبة. عند غياب القناة يُنسخ الرقم للحافظة
/// كي يستطيع المستخدم الاتصال يدويًا.
class EmergencyDialer {
  EmergencyDialer({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'ruview/emergency';

  final MethodChannel _channel;

  Future<DialOutcome> dial(String rawNumber) async {
    final String number = sanitize(rawNumber);
    if (number.isEmpty) return DialOutcome.invalidNumber;

    try {
      final bool? opened = await _channel.invokeMethod<bool>(
        'dial',
        <String, dynamic>{'number': number},
      );
      if (opened ?? false) return DialOutcome.dialerOpened;
    } catch (_) {
      // القناة غير متوفرة — المتابعة بالنسخ.
    }

    try {
      await Clipboard.setData(ClipboardData(text: number));
      return DialOutcome.copiedToClipboard;
    } catch (_) {
      return DialOutcome.invalidNumber;
    }
  }

  /// إزالة كل ما ليس رقمًا أو علامة `+` (الحد الأقصى 20 محرفًا).
  static String sanitize(String rawNumber) {
    final String cleaned = rawNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final String singlePlus =
        cleaned.startsWith('+') ? '+${cleaned.replaceAll('+', '')}' : cleaned.replaceAll('+', '');
    return singlePlus.length > 20 ? singlePlus.substring(0, 20) : singlePlus;
  }
}
