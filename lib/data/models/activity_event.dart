import '../../core/theme/app_colors.dart';

/// تصنيف الحدث — يحدّد الأيقونة واللون في سجل الأنشطة.
enum ActivityKind {
  connection('اتصال'),
  presence('حضور'),
  motion('حركة'),
  breathing('تنفس'),
  signal('إشارة'),
  posture('وضعية'),
  gait('مشية'),
  fall('سقوط'),
  security('أمني'),
  sleep('نوم'),
  system('نظام');

  const ActivityKind(this.arabicLabel);

  final String arabicLabel;
}

/// سطر في سجل الأنشطة الحية أسفل لوحة الرصد.
class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.timestamp,
    required this.tone,
    this.detail,
  });

  final int id;
  final ActivityKind kind;
  final String title;
  final String? detail;
  final DateTime timestamp;
  final StatusTone tone;

  /// وصف زمني نسبي بالعربية: الآن / 12 ث / 3 د / 2 س.
  String relativeTimeLabel(DateTime now) {
    final Duration diff = now.difference(timestamp);
    if (diff.inSeconds < 3) return 'الآن';
    if (diff.inSeconds < 60) return '${diff.inSeconds} ث';
    if (diff.inMinutes < 60) return '${diff.inMinutes} د';
    if (diff.inHours < 24) return '${diff.inHours} س';
    return '${diff.inDays} ي';
  }
}
