import 'dart:math' as math;

import '../../core/utils/num_utils.dart';
import 'json_read.dart';
import 'vital_signs.dart';

/// مستوى الحركة كما تُصنّفه بوابة RuView.
enum MotionLevel {
  absent('absent', 'غائب'),
  still('present_still', 'ساكن'),
  moving('present_moving', 'متحرك'),
  active('active', 'نشط'),
  unknown('unknown', 'غير محدد');

  const MotionLevel(this.wire, this.arabicLabel);

  /// القيمة القادمة من الخادم في `classification.motion_level`.
  final String wire;

  /// الوصف العربي المعروض في الواجهة.
  final String arabicLabel;

  static MotionLevel fromWire(String? value) {
    final String v = (value ?? '').toLowerCase().trim();
    return switch (v) {
      'absent' || 'none' || 'empty' => MotionLevel.absent,
      'present_still' || 'still' || 'idle' || 'sitting' => MotionLevel.still,
      'present_moving' || 'moving' || 'walking' => MotionLevel.moving,
      'active' => MotionLevel.active,
      _ => MotionLevel.unknown,
    };
  }

  bool get isPresence => this != MotionLevel.absent && this != MotionLevel.unknown;

  bool get isMoving => this == MotionLevel.moving || this == MotionLevel.active;
}

/// تصنيف الحضور/الحركة — `classification` في رسالة `sensing_update`.
class ClassificationInfo {
  const ClassificationInfo({
    required this.motionLevel,
    required this.presence,
    required this.confidence,
  });

  const ClassificationInfo.empty()
      : motionLevel = MotionLevel.unknown,
        presence = false,
        confidence = 0;

  factory ClassificationInfo.fromJson(Map<String, dynamic> json) {
    final MotionLevel level =
        MotionLevel.fromWire(JsonRead.asString(json['motion_level']));
    // تتعدد أسماء الحقول بين إصدارات الخادم؛ نقرأ أول قيمة متاحة.
    final Object? rawPresence = json['presence'] ?? json['is_present'];
    final bool presence = rawPresence == null
        ? level.isPresence
        : JsonRead.asBool(rawPresence, level.isPresence);

    return ClassificationInfo(
      motionLevel: level,
      presence: presence || level.isPresence,
      confidence: NumUtils.clamp01(JsonRead.asDouble(json['confidence'])),
    );
  }

  final MotionLevel motionLevel;
  final bool presence;
  final double confidence;

  /// درجة الحركة على مقياس 0..1 (تجمع بين التصنيف وطاقة نطاق الحركة).
  static double intensity({
    required MotionLevel level,
    required double motionBandPower,
  }) {
    final double byLevel = switch (level) {
      MotionLevel.moving || MotionLevel.active => 0.78,
      MotionLevel.still => 0.26,
      MotionLevel.absent => 0.04,
      MotionLevel.unknown => 0.12,
    };
    final double byPower = NumUtils.clamp01(motionBandPower / 2.5);
    return NumUtils.clamp01(math.max(byLevel, byPower));
  }
}

/// ميزات الإشارة المستخرجة من CSI/RSSI.
class FeatureInfo {
  const FeatureInfo({
    required this.meanRssi,
    required this.variance,
    required this.motionBandPower,
    required this.breathingBandPower,
    required this.dominantFreqHz,
    required this.changePoints,
    required this.spectralPower,
  });

  const FeatureInfo.empty()
      : meanRssi = 0,
        variance = 0,
        motionBandPower = 0,
        breathingBandPower = 0,
        dominantFreqHz = 0,
        changePoints = 0,
        spectralPower = 0;

  factory FeatureInfo.fromJson(Map<String, dynamic> json) => FeatureInfo(
        meanRssi: JsonRead.asDouble(json['mean_rssi']),
        variance: JsonRead.asDouble(json['variance']),
        motionBandPower: JsonRead.asDouble(json['motion_band_power']),
        breathingBandPower: JsonRead.asDouble(json['breathing_band_power']),
        dominantFreqHz: JsonRead.asDouble(json['dominant_freq_hz']),
        changePoints: JsonRead.asInt(json['change_points']),
        spectralPower: JsonRead.asDouble(json['spectral_power']),
      );

  final double meanRssi;
  final double variance;
  final double motionBandPower;
  final double breathingBandPower;
  final double dominantFreqHz;
  final int changePoints;
  final double spectralPower;

  /// تقدير جودة الإشارة من RSSI (‎-30 dBm ممتاز … ‎-90 dBm ضعيف).
  double get qualityFromRssi {
    if (meanRssi >= 0) return 0;
    return NumUtils.clamp01(NumUtils.mapRange(meanRssi, -90, -35, 0, 1));
  }
}

/// معلومات عقدة استشعار (ESP32 أو نقطة وصول).
class NodeInfo {
  const NodeInfo({
    required this.nodeId,
    required this.rssiDbm,
    required this.position,
    required this.subcarrierCount,
    required this.amplitude,
    this.frameRateHz,
    this.stale = false,
  });

  factory NodeInfo.fromJson(Map<String, dynamic> json) {
    final List<Object?> rawPosition =
        (json['position'] as List<Object?>?) ?? const <Object?>[];
    return NodeInfo(
      nodeId: JsonRead.asInt(json['node_id']),
      rssiDbm: JsonRead.asDouble(json['rssi_dbm']),
      position: <double>[
        for (final Object? axis in rawPosition) JsonRead.asDouble(axis),
      ],
      subcarrierCount: JsonRead.asInt(json['subcarrier_count']),
      amplitude: JsonRead.asDoubleList(json['amplitude']),
      frameRateHz: JsonRead.asOptionalDouble(json['frame_rate_hz']),
      stale: JsonRead.asBool(json['stale']),
    );
  }

  final int nodeId;
  final double rssiDbm;
  final List<double> position;
  final int subcarrierCount;
  final List<double> amplitude;
  final double? frameRateHz;
  final bool stale;

  /// تقدير جودة الإشارة لهذه العقدة (0..1).
  double get quality => NumUtils.clamp01(
        NumUtils.mapRange(rssiDbm, -90, -35, 0, 1),
      );
}

/// نقطة مفصلية في تقدير الوضعية (17 نقطة COCO).
class PoseKeypoint {
  const PoseKeypoint({
    required this.name,
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
  });

  factory PoseKeypoint.fromJson(Map<String, dynamic> json) => PoseKeypoint(
        name: JsonRead.asString(json['name']),
        x: JsonRead.asDouble(json['x']),
        y: JsonRead.asDouble(json['y']),
        z: JsonRead.asDouble(json['z']),
        confidence: NumUtils.clamp01(JsonRead.asDouble(json['confidence'])),
      );

  final String name;
  final double x;
  final double y;
  final double z;
  final double confidence;
}

/// شخص مرصود داخل المنطقة.
class PersonDetection {
  const PersonDetection({
    required this.id,
    required this.confidence,
    required this.zone,
    required this.position,
    required this.motionScore,
    this.posture,
    this.keypoints = const <PoseKeypoint>[],
  });

  factory PersonDetection.fromJson(Map<String, dynamic> json) {
    final List<Object?> rawPosition =
        (json['position'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> rawKeypoints =
        (json['keypoints'] as List<Object?>?) ?? const <Object?>[];

    return PersonDetection(
      id: JsonRead.asInt(json['id']),
      confidence: NumUtils.clamp01(JsonRead.asDouble(json['confidence'])),
      zone: JsonRead.asString(json['zone']),
      position: <double>[
        for (final Object? axis in rawPosition) JsonRead.asDouble(axis),
      ],
      motionScore: JsonRead.asDouble(json['motion_score']),
      posture: json['pose'] == null ? null : JsonRead.asString(json['pose']),
      keypoints: rawKeypoints
          .map(JsonRead.asMap)
          .where((Map<String, dynamic> map) => map.isNotEmpty)
          .map(PoseKeypoint.fromJson)
          .toList(growable: false),
    );
  }

  final int id;
  final double confidence;
  final String zone;
  final List<double> position;
  final double motionScore;
  final String? posture;
  final List<PoseKeypoint> keypoints;

  double get x => position.isNotEmpty ? position[0] : 0;
  double get y => position.length > 1 ? position[1] : 0;
}

/// شبكة مجال الإشارة (grid) التي تُرسم منها خريطة الحضور.
class SignalField {
  const SignalField({required this.gridSize, required this.values});

  const SignalField.empty()
      : gridSize = const <int>[0, 0, 0],
        values = const <double>[];

  factory SignalField.fromJson(Map<String, dynamic> json) {
    final List<Object?> rawGrid =
        (json['grid_size'] as List<Object?>?) ?? const <Object?>[];
    return SignalField(
      gridSize: <int>[for (final Object? v in rawGrid) JsonRead.asInt(v)],
      values: JsonRead.asDoubleList(json['values']),
    );
  }

  final List<int> gridSize;
  final List<double> values;

  bool get isEmpty => values.isEmpty || gridSize.isEmpty;

  int get width => gridSize.isNotEmpty ? gridSize[0] : 0;
  int get height => gridSize.length > 2 ? gridSize[2] : 0;

  double get peak =>
      values.isEmpty ? 0 : values.reduce((double a, double b) => math.max(a, b));
}

/// إطار الاستشعار الكامل كما تبثّه بوابة RuView على `/ws/sensing`.
///
/// يطابق البنية الرسمية `SensingUpdate` في
/// `wifi-densepose-sensing-server/src/types.rs` مع تسامح مع الحقول الاختيارية
/// واختلاف الأسماء بين الإصدارات.
class SensingFrame {
  const SensingFrame({
    required this.type,
    required this.timestamp,
    required this.receivedAt,
    required this.source,
    required this.tick,
    required this.nodes,
    required this.features,
    required this.classification,
    required this.signalField,
    required this.vitalSigns,
    required this.persons,
    required this.estimatedPersons,
    this.posture,
    this.signalQualityScore,
    this.qualityVerdict,
  });

  factory SensingFrame.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    final List<Map<String, dynamic>> rawNodes = JsonRead.asMapList(json['nodes']);
    final Map<String, dynamic> rawFeatures = JsonRead.asMap(json['features']);
    final Map<String, dynamic> rawClassification =
        JsonRead.asMap(json['classification']);
    final Object? rawVitals = json['vital_signs'] ?? json['vitals'];
    final List<Map<String, dynamic>> rawPersons =
        JsonRead.asMapList(json['persons']);

    // `timestamp` في الخادم الرسمي ثوانٍ عشرية (f64)؛ بعض البوابات ترسله مللي ثانية.
    final double rawTs = JsonRead.asDouble(json['timestamp']);
    final DateTime timestamp = _parseTimestamp(rawTs) ?? DateTime.now();

    final int? estimated = JsonRead.asOptionalInt(json['estimated_persons']);

    return SensingFrame(
      type: JsonRead.asString(json['type'], 'sensing_update'),
      timestamp: timestamp,
      receivedAt: receivedAt ?? DateTime.now(),
      source: JsonRead.asString(json['source'], 'unknown'),
      tick: JsonRead.asInt(json['tick']),
      nodes: rawNodes.map(NodeInfo.fromJson).toList(growable: false),
      features: rawFeatures.isEmpty
          ? const FeatureInfo.empty()
          : FeatureInfo.fromJson(rawFeatures),
      classification: rawClassification.isEmpty
          ? const ClassificationInfo.empty()
          : ClassificationInfo.fromJson(rawClassification),
      signalField: json['signal_field'] == null
          ? const SignalField.empty()
          : SignalField.fromJson(JsonRead.asMap(json['signal_field'])),
      vitalSigns: rawVitals == null
          ? null
          : VitalSigns.fromJson(JsonRead.asMap(rawVitals)),
      persons: rawPersons.map(PersonDetection.fromJson).toList(growable: false),
      estimatedPersons: estimated,
      posture: json['posture'] == null ? null : JsonRead.asString(json['posture']),
      signalQualityScore: JsonRead.asOptionalDouble(json['signal_quality_score']),
      qualityVerdict:
          json['quality_verdict'] == null ? null : JsonRead.asString(json['quality_verdict']),
    );
  }

  static DateTime? _parseTimestamp(double raw) {
    if (raw <= 0) return null;
    // ثوانٍ (‎< 1e11) أم مللي ثانية؟
    if (raw > 1e11) {
      return DateTime.fromMillisecondsSinceEpoch(raw.round());
    }
    return DateTime.fromMillisecondsSinceEpoch((raw * 1000).round());
  }

  final String type;
  final DateTime timestamp;
  final DateTime receivedAt;
  final String source;
  final int tick;
  final List<NodeInfo> nodes;
  final FeatureInfo features;
  final ClassificationInfo classification;
  final SignalField signalField;
  final VitalSigns? vitalSigns;
  final List<PersonDetection> persons;
  final int? estimatedPersons;
  final String? posture;
  final double? signalQualityScore;
  final String? qualityVerdict;

  /// عدد الأشخاص المرصودين (يُفضّل تقدير الخادم ثم عدد الكائنات).
  int get personCount {
    final int? estimated = estimatedPersons;
    if (estimated != null && estimated >= 0) return estimated;
    return persons.length;
  }

  /// هل يوجد شخص في المنطقة؟
  bool get hasPresence => classification.presence || personCount > 0;

  /// شدة الحركة على مقياس 0..1.
  double get motionIntensity => ClassificationInfo.intensity(
        level: classification.motionLevel,
        motionBandPower: features.motionBandPower,
      );

  /// جودة الإشارة على مقياس 0..1 (من الخادم إن وُجدت، وإلا من RSSI).
  double get signalQuality {
    final double? score = signalQualityScore;
    if (score != null) {
      return NumUtils.clamp01(score > 1 ? score / 100.0 : score);
    }
    if (nodes.isEmpty) return 0;
    final double sum = nodes.fold<double>(
      0,
      (double acc, NodeInfo node) => acc + node.quality,
    );
    return NumUtils.clamp01(sum / nodes.length);
  }

  /// متوسط قوة الإشارة بالـ dBm عبر العقد.
  double get averageRssi {
    if (nodes.isEmpty) return features.meanRssi;
    final double sum =
        nodes.fold<double>(0, (double acc, NodeInfo node) => acc + node.rssiDbm);
    return sum / nodes.length;
  }

  double? get breathingRateBpm => vitalSigns?.breathingRateBpm;

  SensingFrame copyWithReceivedAt(DateTime value) => SensingFrame(
        type: type,
        timestamp: timestamp,
        receivedAt: value,
        source: source,
        tick: tick,
        nodes: nodes,
        features: features,
        classification: classification,
        signalField: signalField,
        vitalSigns: vitalSigns,
        persons: persons,
        estimatedPersons: estimatedPersons,
        posture: posture,
        signalQualityScore: signalQualityScore,
        qualityVerdict: qualityVerdict,
      );
}
