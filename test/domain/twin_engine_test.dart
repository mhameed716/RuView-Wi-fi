import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/posture.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/twin/body_profile.dart';
import 'package:ruview_wifi/domain/twin/cloth_simulator.dart';
import 'package:ruview_wifi/domain/twin/twin_engine.dart';
import 'package:ruview_wifi/domain/twin/twin_state.dart';

SensingFrame frame({
  bool presence = true,
  bool withKeypoints = true,
  int tick = 0,
}) {
  const List<String> names = <String>[
    'nose',
    'left_shoulder',
    'right_shoulder',
    'left_elbow',
    'right_elbow',
    'left_wrist',
    'right_wrist',
    'left_hip',
    'right_hip',
    'left_knee',
    'right_knee',
    'left_ankle',
    'right_ankle',
  ];
  const List<List<double>> points = <List<double>>[
    <double>[0.50, 0.10],
    <double>[0.42, 0.24],
    <double>[0.58, 0.24],
    <double>[0.40, 0.36],
    <double>[0.60, 0.36],
    <double>[0.39, 0.46],
    <double>[0.61, 0.46],
    <double>[0.45, 0.52],
    <double>[0.55, 0.52],
    <double>[0.46, 0.72],
    <double>[0.54, 0.72],
    <double>[0.47, 0.92],
    <double>[0.53, 0.92],
  ];

  final Map<String, dynamic> person = <String, dynamic>{
    'id': 1,
    'confidence': 0.9,
    'zone': 'zone_living',
    'position': <double>[2.0, 0, 2.0],
    'pose': 'standing',
    if (withKeypoints)
      'keypoints': <Map<String, dynamic>>[
        for (int i = 0; i < names.length; i++)
          <String, dynamic>{
            'name': names[i],
            'x': points[i][0],
            'y': points[i][1],
            'z': 0,
            'confidence': 0.9,
          },
      ],
  };

  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': 1735000000 + tick,
      'features': <String, dynamic>{
        'motion_band_power': 0.4,
        'variance': 1.5,
        'mean_rssi': -50.0,
      },
      'classification': <String, dynamic>{
        'presence': presence,
        'motion_level': presence ? 'present_moving' : 'absent',
        'confidence': 0.9,
      },
      'persons': presence ? <Map<String, dynamic>>[person] : <Map<String, dynamic>>[],
    },
    receivedAt: DateTime(2026, 1, 1).add(Duration(milliseconds: tick * 120)),
  );
}

List<PoseKeypoint> keypointsOf(SensingFrame frame) =>
    frame.persons.isEmpty ? const <PoseKeypoint>[] : frame.persons.first.keypoints;

void main() {
  group('TwinEngine', () {
    test('يبني جسمًا كاملًا من إطار حقيقي', () {
      final TwinEngine engine = TwinEngine();

      final TwinState state = engine.update(
        frame: frame(),
        posture: PostureKind.standing,
        keypoints: keypointsOf(frame()),
      );

      expect(state.hasBody, isTrue);
      expect(state.hasMesh, isTrue);
      expect(state.mesh.vertexCount, greaterThan(50));
      expect(state.completionScore, greaterThan(0));
      expect(state.completionScore, lessThanOrEqualTo(1));
      expect(state.cloth.length,
          ClothSimulator.defaultCols * ClothSimulator.defaultRows);
      expect(state.joints.length, greaterThanOrEqualTo(13));
      expect(state.updatedAt, isNotNull);
      expect(state.identityLabel, contains('هوية'));
      expect(state.completionLabel, contains('رأس شبكة'));
    });

    test('معالجة عدة إطارات تبني خريطة الغرفة وتُحدّث القماش', () {
      final TwinEngine engine = TwinEngine();
      TwinState state = TwinState.empty;

      for (int tick = 0; tick < 8; tick++) {
        final SensingFrame current = frame(tick: tick);
        state = engine.update(
          frame: current,
          posture: PostureKind.walking,
          keypoints: keypointsOf(current),
          elapsed: const Duration(milliseconds: 120),
        );
      }

      expect(state.room.hasData, isTrue);
      expect(state.room.frames, 8);
      expect(state.room.cells, isNotEmpty);
    });

    test('غياب الحضور لا يُنتج جسمًا لكنه يُبقي خريطة الغرفة', () {
      final TwinEngine engine = TwinEngine();
      engine.update(
        frame: frame(),
        posture: PostureKind.standing,
        keypoints: keypointsOf(frame()),
      );

      final TwinState idle = engine.update(
        frame: frame(presence: false, withKeypoints: false, tick: 3),
        posture: PostureKind.unknown,
        keypoints: const <PoseKeypoint>[],
      );

      expect(idle.hasBody, isFalse);
      expect(idle.room.frames, greaterThan(0));
    });

    test('تسجيل التوأم ثم مطابقته تلقائيًا', () {
      final TwinEngine engine = TwinEngine(
        meshInterval: const Duration(milliseconds: 1),
      );
      final SensingFrame first = frame();
      final TwinState state = engine.update(
        frame: first,
        posture: PostureKind.standing,
        keypoints: keypointsOf(first),
      );
      expect(state.hasBody, isTrue);

      final BodyProfile? profile = engine.enrollProfile('أحمد');
      expect(profile, isNotNull);
      expect(profile!.label, 'أحمد');
      expect(profile.signature.heightM, greaterThan(0));

      engine.setProfiles(<BodyProfile>[profile]);

      final SensingFrame second = frame(tick: 4);
      final TwinState matched = engine.update(
        frame: second,
        posture: PostureKind.standing,
        keypoints: keypointsOf(second),
      );

      expect(matched.match, isNotNull);
      expect(matched.match!.profile.id, profile.id);
      expect(matched.match!.score, greaterThan(0.6));
      expect(matched.identityLabel, contains('أحمد'));
    });

    test('بدون جسم لا يمكن تسجيل توأم', () {
      final TwinEngine engine = TwinEngine();
      expect(engine.enrollProfile('مجهول'), isNull);
    });
  });
}
