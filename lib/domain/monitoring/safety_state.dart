import '../../data/models/gait_profile.dart';
import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import '../../data/models/sleep_summary.dart';

/// تنبيه سقوط — يُستخدم لتشغيل لافتة الطوارئ.
class FallAlert {
  const FallAlert({
    required this.detectedAt,
    required this.confidence,
    required this.posture,
    required this.reason,
  });

  final DateTime detectedAt;
  final double confidence;
  final PostureKind posture;
  final String reason;

  bool get isCritical => confidence >= 0.6;

  String get confidenceLabel => '${(confidence * 100).round()}%';
}

/// تنبيه تسلل في وضع الحراسة الأمنية.
class IntrusionAlert {
  const IntrusionAlert({
    required this.detectedAt,
    required this.motionIntensity,
    required this.confidence,
    this.zone,
  });

  final DateTime detectedAt;
  final double motionIntensity;
  final double confidence;
  final String? zone;
}

/// نتيجة مطابقة المشية لبصمة محفوظة.
class GaitMatch {
  const GaitMatch({
    required this.profile,
    required this.similarity,
    required this.matchedAt,
  });

  final GaitProfile profile;
  final double similarity;
  final DateTime matchedAt;

  String get similarityLabel => '${(similarity * 100).round()}%';
}

/// أنواع الإشارات التي يولّدها [SafetyMonitor] لتُحوَّل إلى سجل الأحداث.
enum SafetySignalKind {
  fall('سقوط محتمل'),
  intrusion('تسلل'),
  gaitRecognized('تعرّف على المشية'),
  gaitEnrolled('تسجيل بصمة مشية'),
  apnea('اضطراب تنفس'),
  postureChanged('تغيّر الوضعية'),
  sleepStateChanged('حالة النوم'),
  armed('وضع الحراسة'),
  disarmed('إيقاف الحراسة');

  const SafetySignalKind(this.arabicLabel);

  final String arabicLabel;

  /// إشارات تستدعي تنبيهًا فوريًا (صوت/اهتزاز/إشعار).
  bool get isCritical =>
      this == SafetySignalKind.fall ||
      this == SafetySignalKind.intrusion ||
      this == SafetySignalKind.apnea;
}

/// إشارة واحدة صادرة عن محرّك السلامة.
class SafetySignal {
  const SafetySignal({
    required this.kind,
    required this.title,
    this.detail,
    this.confidence,
  });

  final SafetySignalKind kind;
  final String title;
  final String? detail;
  final double? confidence;
}

/// الحالة الكاملة للرصد المتقدم (وضعية + سقوط + تسلل + مشية + نوم).
class SafetyState {
  const SafetyState({
    this.posture = PostureKind.unknown,
    this.postureSource = PostureSource.none,
    this.postureConfidence = 0,
    this.keypoints = const <PoseKeypoint>[],
    this.fallAlert,
    this.lastFallAt,
    this.intrusionAlert,
    this.lastIntrusionAt,
    this.intrusionArmed = false,
    this.armedAt,
    this.gaitMatch,
    this.gaitProfiles = const <GaitProfile>[],
    this.gaitCollecting = false,
    this.sleep = const SleepSummary(),
  });

  final PostureKind posture;

  /// من أين جاء تقدير الوضعية (الخادم أم الهاتف).
  final PostureSource postureSource;

  /// ثقة تقدير الوضعية 0..1.
  final double postureConfidence;

  final List<PoseKeypoint> keypoints;
  final FallAlert? fallAlert;
  final DateTime? lastFallAt;
  final IntrusionAlert? intrusionAlert;
  final DateTime? lastIntrusionAt;
  final bool intrusionArmed;
  final DateTime? armedAt;
  final GaitMatch? gaitMatch;
  final List<GaitProfile> gaitProfiles;
  final bool gaitCollecting;
  final SleepSummary sleep;

  bool get hasFallAlert => fallAlert != null;

  bool get hasSkeleton => keypoints.length >= 5;

  SafetyState copyWith({
    PostureKind? posture,
    PostureSource? postureSource,
    double? postureConfidence,
    List<PoseKeypoint>? keypoints,
    FallAlert? fallAlert,
    bool clearFallAlert = false,
    DateTime? lastFallAt,
    IntrusionAlert? intrusionAlert,
    bool clearIntrusionAlert = false,
    DateTime? lastIntrusionAt,
    bool? intrusionArmed,
    DateTime? armedAt,
    GaitMatch? gaitMatch,
    List<GaitProfile>? gaitProfiles,
    bool? gaitCollecting,
    SleepSummary? sleep,
  }) {
    return SafetyState(
      posture: posture ?? this.posture,
      postureSource: postureSource ?? this.postureSource,
      postureConfidence: postureConfidence ?? this.postureConfidence,
      keypoints: keypoints ?? this.keypoints,
      fallAlert: clearFallAlert ? null : (fallAlert ?? this.fallAlert),
      lastFallAt: lastFallAt ?? this.lastFallAt,
      intrusionAlert:
          clearIntrusionAlert ? null : (intrusionAlert ?? this.intrusionAlert),
      lastIntrusionAt: lastIntrusionAt ?? this.lastIntrusionAt,
      intrusionArmed: intrusionArmed ?? this.intrusionArmed,
      armedAt: armedAt ?? this.armedAt,
      gaitMatch: gaitMatch ?? this.gaitMatch,
      gaitProfiles: gaitProfiles ?? this.gaitProfiles,
      gaitCollecting: gaitCollecting ?? this.gaitCollecting,
      sleep: sleep ?? this.sleep,
    );
  }
}

/// مصدر تقدير الوضعية.
enum PostureSource {
  none('غير متوفر'),
  server('الخادم'),
  keypoints('المفاصل'),
  motion('الحركة');

  const PostureSource(this.arabicLabel);

  final String arabicLabel;
}
