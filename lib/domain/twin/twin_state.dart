import '../../data/models/posture.dart';
import 'body_mesh.dart';
import 'body_profile.dart';
import 'body_shape.dart';
import 'room_model.dart';
import 'vec3.dart';

/// لقطة كاملة من «التوأم الراديوي» تُعرض في الواجهة.
///
/// تجمع: الشكل البارامتري (SMPL)، المجسّم المكتمل والمنعّم، القماش المتحرك،
/// هوية الشخص المطابقة، وخريطة الغرفة (RF-SLAM).
class TwinState {
  const TwinState({
    required this.shape,
    required this.joints,
    required this.mesh,
    required this.cloth,
    required this.completionScore,
    required this.observedJoints,
    required this.match,
    required this.room,
    required this.posture,
    required this.hasBody,
    required this.updatedAt,
  });

  static const TwinState empty = TwinState(
    shape: BodyShape.average,
    joints: <String, Vec3>{},
    mesh: BodyMesh.empty,
    cloth: <Vec3>[],
    completionScore: 0,
    observedJoints: 0,
    match: null,
    room: RoomModel.empty,
    posture: PostureKind.unknown,
    hasBody: false,
    updatedAt: null,
  );

  final BodyShape shape;

  final Map<String, Vec3> joints;

  final BodyMesh mesh;

  /// جزيئات القماش المرتسمة على الجسم.
  final List<Vec3> cloth;

  /// نسبة المفاصل التي رصدها CSI فعليًا (0..1).
  final double completionScore;

  final int observedJoints;

  /// التوأم المحفوظ المطابق (إن وُجد).
  final BodyMatch? match;

  final RoomModel room;

  final PostureKind posture;

  final bool hasBody;

  final DateTime? updatedAt;

  bool get hasMesh => !mesh.isEmpty;

  String get completionLabel =>
      '${(completionScore * 100).round()}% مرصود · '
      '${mesh.vertexCount} رأس شبكة';

  String get identityLabel {
    final BodyMatch? current = match;
    if (current == null) return 'هوية غير مسجّلة';
    return '${current.profile.label} · '
        '${(current.score * 100).round()}% تطابق';
  }

  TwinState copyWith({
    RoomModel? room,
    BodyMatch? match,
    bool clearMatch = false,
  }) {
    return TwinState(
      shape: shape,
      joints: joints,
      mesh: mesh,
      cloth: cloth,
      completionScore: completionScore,
      observedJoints: observedJoints,
      match: clearMatch ? null : (match ?? this.match),
      room: room ?? this.room,
      posture: posture,
      hasBody: hasBody,
      updatedAt: updatedAt,
    );
  }
}
