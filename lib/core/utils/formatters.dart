/// أدوات تنسيق للعرض (وقت، مدة، أرقام عائمة) بالعربية.
abstract final class Formatters {
  /// مدة بصيغة `01:23` أو `1:02:03` عند تجاوز الساعة.
  static String duration(Duration duration) {
    final int totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  /// "قبل 12 ث" / "قبل 3 د" لأوقات حديثة.
  static String timeAgo(DateTime time, {DateTime? now}) {
    final Duration diff = (now ?? DateTime.now()).difference(time);
    if (diff.inSeconds < 3) return 'الآن';
    if (diff.inSeconds < 60) return 'قبل ${diff.inSeconds} ث';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} ي';
  }

  /// تقريب إلى منزلة عشرية واحدة، مع شرطة عند غياب القيمة.
  static String decimal(double? value, {int digits = 1}) {
    if (value == null || value.isNaN || value.isInfinite) return '—';
    return value.toStringAsFixed(digits);
  }

  static String integer(int? value) => value == null ? '—' : value.toString();

  /// قوة الإشارة بالـ dBm.
  static String rssi(double value) {
    if (value.isNaN || value == 0) return '—';
    return '${value.toStringAsFixed(0)} dBm';
  }
}
