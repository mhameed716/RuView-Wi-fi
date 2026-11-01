import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/sensing_frame.dart';
import 'safety_state.dart';

/// كاشف التسلل في «وضع الحراسة الأمنية».
///
/// الفكرة: عند تفعيل الحراسة يُفترض أن المنطقة خالية، لذا يجب أن تبقى إشارات
/// CSI مستقرة. أي حضور أو حركة فوق العتبة بعد فترة سماح (لتجاهل حركة المستخدم
/// نفسه عند مغادرة الغرفة) تُعتبر دخيلًا.
class IntrusionDetector {
  IntrusionDetector({
    this.armDelay = const Duration(seconds: 20),
    this.cooldown = const Duration(seconds: 30),
    this.motionThreshold = 0.22,
    this.confidenceThreshold = 0.5,
  });

  /// مهلة السماح بعد التفعيل قبل بدء الإنذار.
  final Duration armDelay;

  /// أقل مدة بين تنبيهين متتاليين.
  final Duration cooldown;

  final double motionThreshold;
  final double confidenceThreshold;

  bool _armed = false;
  DateTime? _armedAt;
  DateTime? _lastAlertAt;

  bool get armed => _armed;

  DateTime? get armedAt => _armedAt;

  /// تفعيل/إيقاف الحراسة.
  void setArmed(bool value, {DateTime? now}) {
    if (_armed == value) return;
    _armed = value;
    _armedAt = value ? (now ?? DateTime.now()) : null;
    if (!value) _lastAlertAt = null;
  }

  /// تقييم إطار. تُرجع تنبيهًا عند رصد دخيل، أو `null`.
  IntrusionAlert? evaluate({
    required SensingFrame frame,
    required double motionIntensity,
    DateTime? now,
  }) {
    if (!_armed) return null;
    final DateTime at = now ?? DateTime.now();
    final DateTime? armedAt = _armedAt;
    if (armedAt == null) return null;
    if (at.difference(armedAt) < armDelay) return null;

    final bool presence = frame.hasPresence;
    final bool moving = motionIntensity >= motionThreshold;
    if (!presence && !moving) return null;

    final DateTime? last = _lastAlertAt;
    if (last != null && at.difference(last) < cooldown) return null;

    final double confidence = NumUtils.clamp01(
      math.max(
        presence ? (0.55 + frame.classification.confidence * 0.4) : 0,
        moving ? 0.6 + motionIntensity * 0.35 : 0,
      ),
    );
    if (confidence < confidenceThreshold) return null;

    _lastAlertAt = at;
    return IntrusionAlert(
      detectedAt: at,
      motionIntensity: motionIntensity,
      confidence: confidence,
      zone: frame.persons.isEmpty ? null : frame.persons.first.zone,
    );
  }

  void reset() {
    _armed = false;
    _armedAt = null;
    _lastAlertAt = null;
  }
}
