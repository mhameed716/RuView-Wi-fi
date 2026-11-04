import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/posture.dart';
import 'vec3.dart';

/// تنفيس الحياة في هيكل مستنتج (بدون مفاصل من البوابة).
///
/// لماذا: كثير من بوابات RuView ترسل `classification` و`features` فقط
/// (وضع «الاستشعار فقط»، ADR-019) بلا `persons[].keypoints`. في هذه الحالة
/// نبني الجسم من السابقة الأنثروبومترية ([BodyDefaults.neutralJoints])، ونضيف
/// حركة تنفّس/تمايل صغيرة حتى لا يبدو المجسّم تمثالًا جامدًا.
///
/// الحركة **عرضية فقط** (بضعة ملّيمترات) ولا تُغيّر القياسات المسجّلة.
abstract final class PoseSynthesizer {
  /// أقصى إزاحة تنفّس بالأمتار.
  static const double maxBreathOffset = 0.018;

  /// يزيح المفاصل إزاحة دورية صغيرة حسب الزمن وشدة الحركة.
  static Map<String, Vec3> alive(
    Map<String, Vec3> joints, {
    required double phase,
    required double motion,
    PostureKind posture = PostureKind.unknown,
  }) {
    if (joints.isEmpty) return joints;
    final double intensity = NumUtils.clamp01(motion);
    final double amplitude = maxBreathOffset * (0.35 + 0.65 * intensity);
    final bool lying =
        posture == PostureKind.lying || posture == PostureKind.fallen;

    final Map<String, Vec3> next = <String, Vec3>{};
    for (final MapEntry<String, Vec3> entry in joints.entries) {
      final Vec3 point = entry.value;
      // موجة تنتشر من الحوض إلى الرأس: تبدو كتنفّس لا كاهتزاز عشوائي.
      final double wave = math.sin(phase * 2.1 - point.y * 4.2);
      final double sway = math.sin(phase * 1.3) * amplitude * 0.5;
      final Vec3 delta = lying
          ? Vec3(0, wave * amplitude * 0.35, sway)
          : Vec3(sway * 0.4, wave * amplitude, sway);
      next[entry.key] = point + delta;
    }
    return next;
  }
}
