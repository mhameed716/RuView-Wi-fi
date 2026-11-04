import '../../core/utils/num_utils.dart';

/// حالة النوم المستنتجة من ثبات التنفس وحركة الجسم.
enum SleepState {
  absent('لا يوجد نائم', 'لا يوجد شخص في وضعية استلقاء أو سكون'),
  awake('مستيقظ/حركة', 'حركة ملحوظة أثناء الجلسة'),
  light('نوم خفيف', 'تنفس موجود مع تقلّب متوسط'),
  deep('نوم عميق', 'تنفس منتظم وحركة شبه معدومة'),
  disturbed('اضطراب تنفس', 'توقف أو تقلّب حاد في إشارة التنفس');

  const SleepState(this.arabicLabel, this.description);

  final String arabicLabel;
  final String description;

  bool get isSleeping => this == SleepState.light || this == SleepState.deep || this == SleepState.disturbed;
}

/// ملخّص جلسة مراقبة النوم والعلامات الحيوية.
class SleepSummary {
  const SleepSummary({
    this.state = SleepState.absent,
    this.session = Duration.zero,
    this.averageBreathing,
    this.breathingVariability = 0,
    this.apneaEvents = 0,
    this.qualityScore = 0,
    this.isMonitoring = false,
    this.samples = 0,
  });

  final SleepState state;

  /// مدة الجلسة الحالية منذ بدء الاستلقاء/السكون.
  final Duration session;

  /// متوسط معدل التنفس في الجلسة (نفس/دقيقة).
  final double? averageBreathing;

  /// الانحراف المعياري لمعدل التنفس — مقياس استقرار التنفس.
  final double breathingVariability;

  /// عدد مرات انقطاع/غياب إشارة التنفس.
  final int apneaEvents;

  /// درجة جودة النوم 0..100.
  final int qualityScore;

  final bool isMonitoring;
  final int samples;

  bool get hasSession => session.inSeconds >= 30;

  SleepSummary copyWith({
    SleepState? state,
    Duration? session,
    double? averageBreathing,
    double? breathingVariability,
    int? apneaEvents,
    int? qualityScore,
    bool? isMonitoring,
    int? samples,
  }) {
    return SleepSummary(
      state: state ?? this.state,
      session: session ?? this.session,
      averageBreathing: averageBreathing ?? this.averageBreathing,
      breathingVariability: breathingVariability ?? this.breathingVariability,
      apneaEvents: apneaEvents ?? this.apneaEvents,
      qualityScore: qualityScore ?? this.qualityScore,
      isMonitoring: isMonitoring ?? this.isMonitoring,
      samples: samples ?? this.samples,
    );
  }

  /// وصف عربي مختصر للعرض (مثال: «جودة عالية»).
  String get qualityLabel {
    if (!hasSession) return 'بانتظار بيانات كافية';
    if (qualityScore >= 80) return 'جودة عالية';
    if (qualityScore >= 60) return 'جودة متوسطة';
    if (qualityScore >= 40) return 'جودة منخفضة';
    return 'جودة ضعيفة — يُنصح بالمراجعة';
  }

  double get qualityRatio => NumUtils.clamp01(qualityScore / 100);
}
