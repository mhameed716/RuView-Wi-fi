import 'dart:math' as math;

import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import 'safety_state.dart';

/// ناتج تقدير الوضعية مع مصدره وثقته.
class PostureEstimate {
  const PostureEstimate({
    required this.posture,
    required this.source,
    required this.confidence,
    this.keypoints = const <PoseKeypoint>[],
  });

  const PostureEstimate.unknown()
      : posture = PostureKind.unknown,
        source = PostureSource.none,
        confidence = 0,
        keypoints = const <PoseKeypoint>[];

  final PostureKind posture;
  final PostureSource source;
  final double confidence;
  final List<PoseKeypoint> keypoints;

  bool get isKnown => posture.isKnown;
}

/// تقدير وضعية الجسم (HAR) من بيانات الإطار.
///
/// أولوية المصادر:
///  1. `posture` على مستوى الإطار (الخادم الرسمي عند تفعيل نموذج الوضعية).
///  2. `persons[].pose` على مستوى الشخص.
///  3. استنتاج هندسي من مفاصل `keypoints` (17 نقطة COCO) — تقريبي.
///  4. الحركة العامة (`motion_level`) كملاذ أخير.
///
/// **ملاحظة صدق هندسي:** الاستنتاج من المفاصل إرشادي (heuristic) وليس نموذجًا
/// عصبيًا عميقًا كما في خط RuView الرسمي؛ التطبيق يفضّل دائمًا قيمة الخادم
/// إن وُجدت.
abstract final class PostureEstimator {
  static const double _minConfidence = 0.2;

  static PostureEstimate estimate(SensingFrame frame) {
    // 1) مستوى الإطار
    final PostureKind serverPosture = PostureKind.fromWire(frame.posture);
    final List<PoseKeypoint> keypoints = _collectKeypoints(frame);
    if (serverPosture.isKnown) {
      return PostureEstimate(
        posture: serverPosture,
        source: PostureSource.server,
        confidence: math.max(frame.classification.confidence, 0.6),
        keypoints: keypoints,
      );
    }

    // 2) مستوى الشخص
    for (final PersonDetection person in frame.persons) {
      final PostureKind personPosture = PostureKind.fromWire(person.posture);
      if (personPosture.isKnown) {
        return PostureEstimate(
          posture: personPosture,
          source: PostureSource.server,
          confidence: person.confidence,
          keypoints: keypoints,
        );
      }
    }

    // 3) من المفاصل
    if (keypoints.length >= 5) {
      final PostureKind fromJoints = fromKeypoints(keypoints);
      if (fromJoints.isKnown) {
        return PostureEstimate(
          posture: fromJoints,
          source: PostureSource.keypoints,
          confidence: 0.55,
          keypoints: keypoints,
        );
      }
    }

    // 4) من الحركة
    if (frame.hasPresence) {
      if (frame.classification.motionLevel.isMoving) {
        return PostureEstimate(
          posture: PostureKind.walking,
          source: PostureSource.motion,
          confidence: frame.classification.confidence * 0.6,
          keypoints: keypoints,
        );
      }
      return PostureEstimate(
        posture: PostureKind.unknown,
        source: PostureSource.none,
        confidence: 0,
        keypoints: keypoints,
      );
    }

    return const PostureEstimate.unknown();
  }

  /// استنتاج الوضعية من إحداثيات المفاصل المطبَّعة (y يتزايد للأسفل).
  static PostureKind fromKeypoints(List<PoseKeypoint> keypoints) {
    final List<PoseKeypoint> visible = keypoints
        .where((PoseKeypoint keypoint) => keypoint.confidence >= _minConfidence)
        .toList(growable: false);
    if (visible.length < 4) return PostureKind.unknown;

    double? yOf(List<String> names, List<int> indices) {
      for (final String name in names) {
        for (final PoseKeypoint keypoint in visible) {
          if (keypoint.name.toLowerCase() == name) return keypoint.y;
        }
      }
      // بعض الخوادم ترسل الإحداثيات بترتيب COCO بدون أسماء.
      final bool anyName = visible.any((PoseKeypoint k) => k.name.isNotEmpty);
      if (!anyName) {
        for (final int index in indices) {
          if (index < keypoints.length) return keypoints[index].y;
        }
      }
      return null;
    }

    final double? nose = yOf(<String>['nose'], <int>[0]);
    final double? shoulder = _average(<double?>[
      yOf(<String>['left_shoulder'], <int>[5]),
      yOf(<String>['right_shoulder'], <int>[6]),
    ]);
    final double? hip = _average(<double?>[
      yOf(<String>['left_hip'], <int>[11]),
      yOf(<String>['right_hip'], <int>[12]),
    ]);
    final double? knee = _average(<double?>[
      yOf(<String>['left_knee'], <int>[13]),
      yOf(<String>['right_knee'], <int>[14]),
    ]);

    final double minY = visible
        .map((PoseKeypoint k) => k.y)
        .reduce((double a, double b) => math.min(a, b));
    final double maxY = visible
        .map((PoseKeypoint k) => k.y)
        .reduce((double a, double b) => math.max(a, b));
    final double span = maxY - minY;

    // جسم أفقي = استلقاء (أو سقوط على الأرض).
    if (span > 0 && span < 0.22) return PostureKind.lying;

    // الرأس تحت مستوى الكتفين = انحناء/انحناء لالتقاط شيء.
    if (nose != null && shoulder != null && nose > shoulder + 0.1) {
      return PostureKind.bending;
    }

    // الحوض في مستوى الركبة تقريبًا مع امتداد الجسم = جلوس.
    if (hip != null && knee != null && (hip - knee).abs() < 0.08) {
      return PostureKind.sitting;
    }

    if (span >= 0.45) return PostureKind.standing;

    return PostureKind.unknown;
  }

  static double? _average(List<double?> values) {
    final List<double> present =
        values.whereType<double>().toList(growable: false);
    if (present.isEmpty) return null;
    return present.reduce((double a, double b) => a + b) / present.length;
  }

  static List<PoseKeypoint> _collectKeypoints(SensingFrame frame) {
    for (final PersonDetection person in frame.persons) {
      if (person.keypoints.length >= 5) return person.keypoints;
    }
    return const <PoseKeypoint>[];
  }
}
