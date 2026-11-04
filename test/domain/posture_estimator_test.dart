import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/monitoring/posture_estimator.dart';
import 'package:ruview_wifi/domain/monitoring/safety_state.dart';

/// إطار استشعار مبسّط للاختبارات.
SensingFrame buildFrame({
  String? posture,
  List<Map<String, dynamic>>? persons,
  String motionLevel = 'present_moving',
  bool presence = true,
  double motionPower = 0.5,
  DateTime? receivedAt,
}) {
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'source': 'esp32',
      'timestamp': 1793562081.919,
      'features': <String, dynamic>{
        'motion_band_power': motionPower,
        'dominant_freq_hz': 1.4,
        'variance': 2.0,
      },
      'classification': <String, dynamic>{
        'motion_level': motionLevel,
        'presence': presence,
        'confidence': 0.85,
      },
      'nodes': <Map<String, dynamic>>[
        <String, dynamic>{'node_id': 1, 'rssi_dbm': -42},
      ],
      if (posture != null) 'posture': posture,
      if (persons != null) 'persons': persons,
    },
    receivedAt: receivedAt ?? DateTime(2026, 1, 1, 12),
  );
}

Map<String, dynamic> keypoint(String name, double x, double y) =>
    <String, dynamic>{
      'name': name,
      'x': x,
      'y': y,
      'z': 0.0,
      'confidence': 0.9,
    };

/// جسم واقف: رأس أعلى وكتفان وحوض وركبتان — امتداد رأسي كبير.
List<Map<String, dynamic>> standingKeypoints() => <Map<String, dynamic>>[
      keypoint('nose', 0.5, 0.10),
      keypoint('left_shoulder', 0.42, 0.22),
      keypoint('right_shoulder', 0.58, 0.22),
      keypoint('left_hip', 0.45, 0.50),
      keypoint('right_hip', 0.55, 0.50),
      keypoint('left_knee', 0.46, 0.72),
      keypoint('right_knee', 0.54, 0.72),
    ];

/// جسم مستلقٍ: كل المفاصل في شريط رأسي ضيق.
List<Map<String, dynamic>> lyingKeypoints() => <Map<String, dynamic>>[
      keypoint('nose', 0.15, 0.60),
      keypoint('left_shoulder', 0.30, 0.62),
      keypoint('right_shoulder', 0.30, 0.66),
      keypoint('left_hip', 0.62, 0.64),
      keypoint('right_hip', 0.62, 0.68),
      keypoint('left_knee', 0.82, 0.65),
      keypoint('right_knee', 0.82, 0.69),
    ];

/// جسم جالس: الحوض قريب من مستوى الركبة.
List<Map<String, dynamic>> sittingKeypoints() => <Map<String, dynamic>>[
      keypoint('nose', 0.5, 0.15),
      keypoint('left_shoulder', 0.42, 0.28),
      keypoint('right_shoulder', 0.58, 0.28),
      keypoint('left_hip', 0.45, 0.55),
      keypoint('right_hip', 0.55, 0.55),
      keypoint('left_knee', 0.46, 0.60),
      keypoint('right_knee', 0.54, 0.60),
    ];

void main() {
  group('PostureEstimator', () {
    test('يعطي الأولوية لوضعية الخادم على مستوى الإطار', () {
      final PostureEstimate estimate = PostureEstimator.estimate(
        buildFrame(
          posture: 'sitting',
          persons: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'confidence': 0.9,
              'pose': 'standing',
              'keypoints': standingKeypoints(),
            },
          ],
        ),
      );

      expect(estimate.posture, PostureKind.sitting);
      expect(estimate.source, PostureSource.server);
      expect(estimate.confidence, greaterThan(0.5));
    });

    test('يستخدم وضعية الشخص عند غياب وضعية الإطار', () {
      final PostureEstimate estimate = PostureEstimator.estimate(
        buildFrame(
          persons: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'confidence': 0.8,
              'pose': 'lying_down',
              'keypoints': lyingKeypoints(),
            },
          ],
        ),
      );

      expect(estimate.posture, PostureKind.lying);
      expect(estimate.source, PostureSource.server);
      expect(estimate.keypoints, isNotEmpty);
    });

    test('يستنتج الوقوف من المفاصل', () {
      final PostureEstimate estimate = PostureEstimator.estimate(
        buildFrame(
          posture: null,
          persons: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'confidence': 0.8,
              'keypoints': standingKeypoints(),
            },
          ],
        ),
      );

      expect(estimate.posture, PostureKind.standing);
      expect(estimate.source, PostureSource.keypoints);
    });

    test('يستنتج الاستلقاء والجلوس من المفاصل', () {
      expect(
        PostureEstimator.fromKeypoints(
          lyingKeypoints().map(PoseKeypoint.fromJson).toList(),
        ),
        PostureKind.lying,
      );
      expect(
        PostureEstimator.fromKeypoints(
          sittingKeypoints().map(PoseKeypoint.fromJson).toList(),
        ),
        PostureKind.sitting,
      );
    });

    test('يتحمّل مفاصل ناقصة دون استثناء', () {
      expect(
        PostureEstimator.fromKeypoints(const <PoseKeypoint>[]),
        PostureKind.unknown,
      );
    });

    test('يستخدم الحركة كملاذ أخير', () {
      final PostureEstimate moving = PostureEstimator.estimate(
        buildFrame(motionLevel: 'present_moving'),
      );
      expect(moving.posture, PostureKind.walking);
      expect(moving.source, PostureSource.motion);

      final PostureEstimate still = PostureEstimator.estimate(
        buildFrame(motionLevel: 'present_still', motionPower: 0.05),
      );
      expect(still.posture, PostureKind.unknown);
      expect(still.source, PostureSource.none);
    });

    test('يعيد «غير محدد» عند غياب الحضور', () {
      final PostureEstimate estimate = PostureEstimator.estimate(
        buildFrame(motionLevel: 'absent', presence: false),
      );

      expect(estimate.posture, PostureKind.unknown);
      expect(estimate.source, PostureSource.none);
      expect(estimate.confidence, 0);
    });

    test('يطبّع المرادفات العربية/الإنجليزية للوضعية', () {
      expect(PostureKind.fromWire('on_bed'), PostureKind.lying);
      expect(PostureKind.fromWire('Seated'), PostureKind.sitting);
      expect(PostureKind.fromWire('fall_detected'), PostureKind.fallen);
      expect(PostureKind.fromWire('غير معروف'), PostureKind.unknown);
    });
  });
}
