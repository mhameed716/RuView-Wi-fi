/// وضعية الجسم كما يقدّرها خادم RuView أو محرّك التقدير المحلي.
///
/// الخادم الرسمي يرسل الحقل النصي `posture` على مستوى الإطار، و`persons[].pose`
/// على مستوى الشخص. بعض الإصدارات تستخدم مرادفات مختلفة، لذلك نطبّع القيمة
/// عبر [PostureKind.fromWire] قبل تحويلها إلى واجهة عربية.
enum PostureKind {
  standing(
    'standing',
    'واقف',
    <String>['stand', 'standing', 'upright', 'vertical'],
  ),
  sitting(
    'sitting',
    'جالس',
    <String>['sit', 'sitting', 'seated', 'chair', 'on_chair'],
  ),
  lying(
    'lying',
    'مستلقٍ',
    <String>['lie', 'lying', 'lying_down', 'supine', 'on_bed', 'sleeping', 'recumbent'],
  ),
  walking(
    'walking',
    'يمشي',
    <String>['walk', 'walking', 'strolling', 'pacing'],
  ),
  bending(
    'bending',
    'ينحني',
    <String>['bend', 'bending', 'crouch', 'crouching', 'kneel', 'kneeling'],
  ),
  fallen(
    'fallen',
    'سقوط',
    <String>['fall', 'fallen', 'fall_detected', 'collapsed', 'on_floor'],
  ),
  unknown(
    'unknown',
    'غير محدد',
    <String>[],
  );

  const PostureKind(this.wire, this.arabicLabel, this.aliases);

  /// القيمة المعيارية التي يفهمها/يرسلها الخادم.
  final String wire;

  /// النص العربي المعروض في الواجهة.
  final String arabicLabel;

  /// مرادفات شائعة في إصدارات وبوابات مختلفة.
  final List<String> aliases;

  /// تحويل نص الخادم إلى وضعية معروفة (يتحمّل المسافات والشرطات والحالة).
  static PostureKind fromWire(String? value) {
    final String normalized = (value ?? '')
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[\s\-]+'), '_');
    if (normalized.isEmpty) return PostureKind.unknown;
    for (final PostureKind kind in PostureKind.values) {
      if (kind.wire == normalized ||
          kind.aliases.contains(normalized) ||
          normalized.contains(kind.wire)) {
        return kind;
      }
    }
    return PostureKind.unknown;
  }

  /// وضعية منخفضة على مستوى الأرض (يستخدمها كاشف السقوط والنوم).
  bool get isLowLevel => this == PostureKind.lying || this == PostureKind.fallen;

  /// وضعية قائمة/جلوس مرتفعة مركز الكتلة.
  bool get isUpright =>
      this == PostureKind.standing ||
      this == PostureKind.walking ||
      this == PostureKind.sitting ||
      this == PostureKind.bending;

  bool get isKnown => this != PostureKind.unknown;
}
