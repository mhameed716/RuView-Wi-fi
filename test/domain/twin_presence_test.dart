import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/twin/twin_engine.dart';
import 'package:ruview_wifi/domain/twin/twin_state.dart';
import 'package:ruview_wifi/domain/twin/vec3.dart';

/// إطار «وضع الاستشعار فقط»: حضور وتصنيف وحركة بلا أي مفاصل — وهو ما ترسله
/// معظم بوابات RuView في الواقع.
SensingFrame presenceOnlyFrame({
  bool presence = true,
  String motionLevel = 'present_moving',
  double motionPower = 0.9,
  int second = 0,
}) {
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'features': <String, dynamic>{
        'motion_band_power': motionPower,
        'dominant_freq_hz': 1.2,
        'variance': 1.7,
      },
      'classification': <String, dynamic>{
        'motion_level': motionLevel,
        'presence': presence,
        'confidence': 0.86,
      },
    },
    receivedAt: DateTime(2026, 1, 1, 20, 0, second),
  );
}

SensingFrame frameWithKeypoints() {
  const List<String> names = <String>[
    'nose',
    'left_shoulder',
    'right_shoulder',
    'left_hip',
    'right_hip',
    'left_knee',
    'right_knee',
    'left_ankle',
    'right_ankle',
  ];
  const List<List<double>> coords = <List<double>>[
    <double>[0.5, 0.10],
    <double>[0.42, 0.24],
    <double>[0.58, 0.24],
    <double>[0.45, 0.52],
    <double>[0.55, 0.52],
    <double>[0.46, 0.72],
    <double>[0.54, 0.72],
    <double>[0.47, 0.92],
    <double>[0.53, 0.92],
  ];
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'classification': <String, dynamic>{
        'motion_level': 'present_moving',
        'presence': true,
        'confidence': 0.9,
      },
      'persons': <dynamic>[
        <String, dynamic>{
          'id': 1,
          'confidence': 0.9,
          'pose': 'walking',
          'keypoints': <dynamic>[
            for (int i = 0; i < names.length; i++)
              <String, dynamic>{
                'name': names[i],
                'x': coords[i][0],
                'y': coords[i][1],
                'z': 0,
                'confidence': 0.9,
              },
          ],
        },
      ],
    },
    receivedAt: DateTime(2026, 1, 1, 20),
  );
}

void main() {
  group('التوأم الراديوي: الحضور يكفي لرسم الجسم', () {
    test('بوابة بلا مفاصل: يُبنى مجسّم كامل ويُعلَّم أنه مستنتج', () {
      final TwinEngine engine = TwinEngine();
      final SensingFrame frame = presenceOnlyFrame();

      expect(frame.hasPresence, isTrue);
      expect(frame.persons, isEmpty);

      final TwinState state = engine.update(
        frame: frame,
        posture: PostureKind.walking,
        keypoints: const <PoseKeypoint>[],
      );

      expect(state.hasBody, isTrue, reason: 'الحضور وحده يجب أن يُظهر جسمًا');
      expect(state.hasMesh, isTrue, reason: 'المجسّم لم يُبنَ');
      expect(state.poseInferred, isTrue);
      expect(state.mesh.vertexCount, greaterThan(100));
      expect(state.joints.length, greaterThanOrEqualTo(16));
      expect(state.poseSourceLabel, contains('مستنتج'));
    });

    test('حركة التنفّس تُغيّر مواضع المفاصل بين إطارين', () {
      final TwinEngine engine = TwinEngine(
        meshInterval: const Duration(milliseconds: 0),
      );

      final TwinState first = engine.update(
        frame: presenceOnlyFrame(second: 0),
        posture: PostureKind.standing,
        keypoints: const <PoseKeypoint>[],
        elapsed: const Duration(milliseconds: 40),
      );
      final Vec3? neckA = first.joints['neck'];

      final TwinState second = engine.update(
        frame: presenceOnlyFrame(second: 1, motionPower: 0.4),
        posture: PostureKind.standing,
        keypoints: const <PoseKeypoint>[],
        elapsed: const Duration(milliseconds: 700),
      );
      final Vec3? neckB = second.joints['neck'];

      expect(neckA, isNotNull);
      expect(neckB, isNotNull);
      final double delta = (neckB! - neckA!).length;
      expect(delta, greaterThan(0.0005), reason: 'الهيكل المستنتج جامد');
    });

    test('مفاصل البوابة تُستخدم عند وجودها ولا تُعلَّم مستنتجة', () {
      final TwinEngine engine = TwinEngine();
      final SensingFrame frame = frameWithKeypoints();

      final TwinState state = engine.update(
        frame: frame,
        posture: PostureKind.walking,
        keypoints: frame.persons.first.keypoints,
      );

      expect(state.hasBody, isTrue);
      expect(state.hasMesh, isTrue);
      expect(state.poseInferred, isFalse);
      expect(state.observedJoints, greaterThanOrEqualTo(5));
      expect(state.poseSourceLabel, contains('البوابة'));
    });

    test('غياب الحضور يخفي المجسّم ويُبقي الغرفة', () {
      final TwinEngine engine = TwinEngine();
      engine.update(
        frame: presenceOnlyFrame(),
        posture: PostureKind.walking,
        keypoints: const <PoseKeypoint>[],
      );

      final TwinState absent = engine.update(
        frame: presenceOnlyFrame(
          presence: false,
          motionLevel: 'absent',
          second: 3,
        ),
        posture: PostureKind.unknown,
        keypoints: const <PoseKeypoint>[],
      );

      expect(absent.hasBody, isFalse);
      expect(absent.hasMesh, isFalse);
      expect(absent.poseInferred, isFalse);
    });
  });
}
