import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import '../../data/models/posture.dart';
import 'safety_state.dart';

/// كاشف السقوط.
///
/// المنطق المبني على فيزياء CSI:
///   • مركز كتلة الجسم ينتقل من وضعية مرتفعة (وقوف/مشي، وأحيانًا جلوس) إلى
///     مستوى منخفض (استلقاء/أرضية) في زمن قصير جدًا (< [transitionWindow]).
///   • يرافق الانتقال تغيّر حاد وكبير في طاقة الحركة (`motion_band_power`).
///
/// كما يدعم الإبلاغ المباشر من الخادم (`posture: fallen`, أو `pose: fallen`)
/// عند تفعيل نموذج السقوط الرسمي.
class FallDetector {
  FallDetector({
    this.transitionWindow = const Duration(seconds: 2),
    this.motionSpikeThreshold = 0.55,
    this.cooldown = const Duration(seconds: 15),
  });

  /// أقصى مدة يُعتبر خلالها الانتقال من وضعية مرتفعة إلى منخفضة «سقوطًا».
  final Duration transitionWindow;

  /// أدنى شدّة حركة مرافقة (0..1).
  final double motionSpikeThreshold;

  /// منع تكرار التنبيه لنفس الحادثة.
  final Duration cooldown;

  _PostureSample? _lastUpright;
  DateTime? _lastAlertAt;

  /// آخر تنبيه صادر (للعرض والتشخيص).
  FallAlert? lastAlert;

  /// تقييم إطار جديد. تُرجع تنبيهًا عند التحقق، أو `null`.
  FallAlert? evaluate({
    required PostureKind posture,
    required double motionIntensity,
    required DateTime now,
    bool serverReportedFall = false,
  }) {
    // 1) الخادم أبلغ عن سقوط — أعلى ثقة.
    if (serverReportedFall) {
      if (_allowed(now)) {
        final FallAlert alert = FallAlert(
          detectedAt: now,
          confidence: 0.95,
          posture: posture.isKnown ? posture : PostureKind.fallen,
          reason: 'أبلغ خادم RuView عن سقوط',
        );
        return _raise(alert, now);
      }
      return null;
    }

    // 2) تتبّع آخر وضعية مرتفعة.
    if (posture.isUpright) {
      _lastUpright = _PostureSample(posture: posture, at: now);
      return null;
    }

    if (!posture.isLowLevel) return null;

    final _PostureSample? previous = _lastUpright;
    if (previous == null) return null;

    final Duration elapsed = now.difference(previous.at);
    if (elapsed > transitionWindow) return null;
    if (!_allowed(now)) return null;

    final bool fromStanding = previous.posture == PostureKind.standing ||
        previous.posture == PostureKind.walking;
    // الجلوس على الكرسي ثم الاستلقاء تدريجيًا ليس سقوطًا إلا مع حركة عنيفة.
    if (!fromStanding && motionIntensity < 0.75) return null;
    if (motionIntensity < motionSpikeThreshold) return null;

    final double speedFactor = 1 -
        NumUtils.clamp01(
          elapsed.inMilliseconds /
              math.max(1, transitionWindow.inMilliseconds),
        );
    final double confidence = NumUtils.clamp01(
      0.55 + motionIntensity * 0.3 + speedFactor * 0.15,
    );

    final FallAlert alert = FallAlert(
      detectedAt: now,
      confidence: confidence,
      posture: posture,
      reason: fromStanding
          ? 'انتقال سريع من ${previous.posture.arabicLabel} إلى ${posture.arabicLabel}'
          : 'حركة عنيفة أعقبها استلقاء على الأرض',
    );
    return _raise(alert, now);
  }

  /// إعادة التهيئة عند تغيير الاتصال.
  void reset() {
    _lastUpright = null;
    _lastAlertAt = null;
    lastAlert = null;
  }

  bool _allowed(DateTime now) {
    final DateTime? last = _lastAlertAt;
    return last == null || now.difference(last) >= cooldown;
  }

  FallAlert _raise(FallAlert alert, DateTime now) {
    _lastAlertAt = now;
    _lastUpright = null;
    lastAlert = alert;
    return alert;
  }
}

class _PostureSample {
  const _PostureSample({required this.posture, required this.at});

  final PostureKind posture;
  final DateTime at;
}
