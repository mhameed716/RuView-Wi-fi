import '../../core/utils/num_utils.dart';
import '../../data/models/gait_profile.dart';
import '../../data/models/posture.dart';
import '../../data/models/sensing_frame.dart';
import 'body_mesh.dart';
import 'body_profile.dart';
import 'body_shape.dart';
import 'cloth_simulator.dart';
import 'room_model.dart';
import 'room_reconstructor.dart';
import 'shape_completion.dart';
import 'twin_state.dart';
import 'vec3.dart';

/// محرّك «التوأم الراديوي»: يحوّل إطارات CSI إلى جسم ثلاثي الأبعاد حيّ + غرفة.
///
/// خط المعالجة لكل إطار:
///  1. **شكل بارامتري (SMPL)** من المفاصل المرصودة.
///  2. **إكمال تنبئي** للمفاصل المفقودة (سابقة أنثروبومترية + تماثل).
///  3. **تنعيم السطح** (لابلاس/Taubin) لإزالة ضجيج الانعكاس.
///  4. **محاكاة قماش** تتأثر بحركة الجسم.
///  5. **مطابقة التوأم المحفوظ** (بصمة قياسات جسدية + مشية).
///  6. **إعادة بناء الغرفة** (RF-SLAM) وخامات PBR.
///
/// المحرّك نقي (بلا Flutter وبلا شبكة) لذا يُختبر مباشرة.
class TwinEngine {
  TwinEngine({
    RoomReconstructor? room,
    ClothSimulator? cloth,
    this.meshInterval = const Duration(milliseconds: 220),
    this.profileBlend = 0.3,
  })  : _room = room ?? RoomReconstructor(),
        _cloth = cloth ?? ClothSimulator();

  /// أقل مدة بين إعادة بناء الشبكة (توفير للمعالج).
  final Duration meshInterval;

  /// نسبة مزج الشكل الحالي مع التوأم المحفوظ عند مطابقة قوية.
  final double profileBlend;

  final RoomReconstructor _room;
  final ClothSimulator _cloth;

  List<BodyProfile> _profiles = const <BodyProfile>[];
  TwinState _state = TwinState.empty;
  DateTime? _lastMeshAt;
  PostureKind _lastPosture = PostureKind.unknown;
  BodyShape _lastShape = BodyShape.average;

  TwinState get state => _state;

  RoomModel get room => _room.model;

  List<BodyProfile> get profiles => _profiles;

  void setProfiles(List<BodyProfile> profiles) {
    _profiles = List<BodyProfile>.unmodifiable(profiles);
  }

  /// أحدث بصمة شكلية (تُستخدم عند تسجيل توأم جديد).
  BodySignature? get latestSignature => _state.hasBody
      ? BodySignature.fromShape(_state.shape)
      : null;

  /// معالجة إطار جديد. يعيد اللقطة المحدّثة.
  TwinState update({
    required SensingFrame frame,
    required PostureKind posture,
    required List<PoseKeypoint> keypoints,
    GaitFeatureVector? gait,
    Duration elapsed = const Duration(milliseconds: 33),
  }) {
    final RoomModel room = _room.ingest(frame);

    final bool presence = frame.hasPresence && keypoints.isNotEmpty;
    if (!presence) {
      _state = _state.copyWith(room: room);
      if (keypoints.isEmpty) {
        _cloth.settle();
      }
      return _state;
    }

    BodyShape shape = BodyShapeEstimator.estimate(
      keypoints: keypoints,
      posture: posture,
    );

    final Map<String, Vec3> observed = JointProjector.project(
      keypoints: keypoints,
      shape: shape,
    );

    final ShapeCompletionResult completion = ShapeCompleter.complete(
      observed: observed,
      shape: shape,
      posture: posture,
    );

    final List<double> gaitVector = gait?.toVector() ?? const <double>[];
    final BodySignature signature = BodySignature.fromShape(
      shape,
      gaitVector: gaitVector,
    );
    final BodyMatch? match = BodyRecognizer.match(signature, _profiles);

    // استدعاء التوأم المحفوظ: يُثبّت القياسات ويقلّل الاهتزاز بين الإطارات.
    if (match != null && match.score >= 0.8) {
      shape = shape.mixed(match.profile.shape, profileBlend);
    }
    // تنعيم زمني خفيف للشكل لتقليل الوميض.
    shape = shape.mixed(_lastShape, 0.35);

    final DateTime now = DateTime.now();
    final bool rebuildMesh = _state.mesh.isEmpty ||
        _lastMeshAt == null ||
        now.difference(_lastMeshAt!) >= meshInterval ||
        posture != _lastPosture;

    BodyMesh mesh = _state.mesh;
    bool clothReset = false;
    if (rebuildMesh) {
      mesh = BodyMeshBuilder.build(joints: completion.joints, shape: shape);
      mesh = ShapeCompleter.smooth(mesh, iterations: 2);
      _lastMeshAt = now;
      _lastPosture = posture;
      clothReset = true;
    }

    if (clothReset || !_cloth.isReady) {
      _cloth.reset(joints: completion.joints, shape: shape);
    }

    final double seconds = NumUtils.clampRange(
      elapsed.inMilliseconds / 1000,
      0.008,
      0.05,
    );
    _cloth.step(
      seconds,
      motion: frame.motionIntensity,
      wind: Vec3(0.12, 0, 0.65),
    );

    _lastShape = shape;
    _state = TwinState(
      shape: shape,
      joints: completion.joints,
      mesh: mesh,
      cloth: _cloth.particles,
      completionScore: completion.score,
      observedJoints: completion.observed,
      match: match,
      room: room,
      posture: posture,
      hasBody: true,
      updatedAt: now,
    );
    return _state;
  }

  /// تسجيل توأم جديد من الحالة الحالية.
  BodyProfile? enrollProfile(
    String label, {
    GaitFeatureVector? gait,
    DateTime? now,
  }) {
    if (!_state.hasBody) return null;
    final String name = label.trim().isEmpty ? 'شخص' : label.trim();
    final BodySignature signature = BodySignature.fromShape(
      _state.shape,
      gaitVector: gait?.toVector() ?? const <double>[],
    );
    final String id =
        '${BodyRecognizer.fingerprint(signature)}-${_profiles.length + 1}';
    return BodyProfile(
      id: id,
      label: name,
      shape: _state.shape,
      signature: signature,
      enrolledAt: now ?? DateTime.now(),
    );
  }

  void resetBody() {
    _state = _state.copyWith(clearMatch: true);
    _lastShape = BodyShape.average;
    _lastMeshAt = null;
    _lastPosture = PostureKind.unknown;
  }

  void resetRoom() => _room.reset();
}
