import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/utils/num_utils.dart';

/// حزمة CSI خام من عقدة ESP32 (ADR-018).
///
/// الترويسة 20 بايت (little-endian) كما في البرنامج الثابت الرسمي:
/// ```
/// 0  u32 magic = 0xC5110001
/// 4  u8  node_id
/// 5  u8  antennas
/// 6  u16 n_subcarriers
/// 8  u32 freq_mhz
/// 12 u32 sequence
/// 16 i8  rssi
/// 17 i8  noise_floor
/// 18 u8  ppdu_type   (ADR-110)
/// 19 u8  reserved
/// 20 …  I/Q  لكل ناقل فرعي (int8)
/// ```
class Esp32CsiFrame {
  const Esp32CsiFrame({
    required this.nodeId,
    required this.antennas,
    required this.subcarrierCount,
    required this.frequencyMhz,
    required this.sequence,
    required this.rssi,
    required this.noiseFloor,
    required this.ppduType,
    required this.amplitudes,
  });

  static const int magic = 0xC5110001;
  static const int headerBytes = 20;
  static const int maxSubcarriers = 512;

  final int nodeId;
  final int antennas;
  final int subcarrierCount;
  final int frequencyMhz;
  final int sequence;
  final int rssi;
  final int noiseFloor;
  final int ppduType;

  /// سعة كل ناقل فرعي: `sqrt(I² + Q²)`.
  final List<double> amplitudes;

  double get meanAmplitude => amplitudes.isEmpty
      ? 0
      : amplitudes.reduce((double a, double b) => a + b) / amplitudes.length;

  /// محاولة تحليل حزمة ثنائية. تُرجع `null` إذا لم تكن الحزمة بصيغة ESP32.
  static Esp32CsiFrame? tryParse(Uint8List data) {
    if (data.length < headerBytes) return null;
    final ByteData view = ByteData.sublistView(data);
    if (view.getUint32(0, Endian.little) != magic) return null;

    final int nodeId = data[4];
    final int antennas = data[5];
    final int nSub = view.getUint16(6, Endian.little);
    if (nSub <= 0 || nSub > maxSubcarriers) return null;

    final int declaredBytes = headerBytes + nSub * 2;
    if (data.length < declaredBytes) return null;

    final int freqMhz = view.getUint32(8, Endian.little);
    final int sequence = view.getUint32(12, Endian.little);
    final int rssi = view.getInt8(16);
    final int noiseFloor = view.getInt8(17);
    final int ppduType = data[18];

    final List<double> amplitudes = List<double>.filled(nSub, 0);
    for (int i = 0; i < nSub; i++) {
      final int offset = headerBytes + i * 2;
      final int iValue = view.getInt8(offset);
      final int qValue = view.getInt8(offset + 1);
      amplitudes[i] = math.sqrt(
        (iValue * iValue + qValue * qValue).toDouble(),
      );
    }

    return Esp32CsiFrame(
      nodeId: nodeId,
      antennas: antennas,
      subcarrierCount: nSub,
      frequencyMhz: freqMhz,
      sequence: sequence,
      rssi: rssi,
      noiseFloor: noiseFloor,
      ppduType: ppduType,
      amplitudes: amplitudes,
    );
  }
}

/// محلّل إشارة محلي لعُقد UDP.
///
/// ملاحظة هندسية مهمة: خادم RuView الرسمي هو من يحسب `signal_field` وبصمة
/// الوضعية بدقة. هذا المحلّل **بديل خفيف** يعمل داخل الهاتف عندما يبثّ
/// ESP32 حزم CSI خامًا مباشرة إلى التطبيق (بدون بوابة)، ويستخرج:
///   • طاقة الحركة (تشتّت السعة بين إطارين متتاليين)
///   • الحضور (تباين متوسط السعة)
///   • معدل تنفس تقديري (معدل تقاطع صفري للسعة منزوعة الاتجاه)
///
/// النتيجة تُصاغ كرسالة `sensing_update` بنفس بنية الخادم الرسمي حتى تعمل
/// بقية طبقات التطبيق دون تغيير.
class CsiAnalyzer {
  CsiAnalyzer({
    this.windowSize = 32,
    this.breathingWindow = const Duration(seconds: 30),
  });

  /// عدد الإطارات المحتفظ بها لحساب التباين وطاقة الحركة.
  final int windowSize;

  /// طول نافذة تقدير التنفس.
  final Duration breathingWindow;

  final Map<int, _NodeState> _nodes = <int, _NodeState>{};
  int _sequenceCounter = 0;
  int _packets = 0;
  int _dropped = 0;
  double _frameRate = 0;
  DateTime? _lastFrameAt;

  int get packetCount => _packets;
  int get droppedCount => _dropped;
  double get frameRateHz => _frameRate;

  /// إعادة التهيئة عند تغيير الاتصال.
  void reset() {
    _nodes.clear();
    _sequenceCounter = 0;
    _packets = 0;
    _dropped = 0;
    _frameRate = 0;
    _lastFrameAt = null;
  }

  /// تمرير حزمة UDP خام. تُرجع `null` إذا لم تُطابق صيغة ESP32.
  Map<String, dynamic>? ingest(Uint8List data, {DateTime? receivedAt}) {
    final Esp32CsiFrame? frame = Esp32CsiFrame.tryParse(data);
    if (frame == null) {
      _dropped++;
      return null;
    }

    final DateTime now = receivedAt ?? DateTime.now();
    final _NodeState state = _nodes.putIfAbsent(frame.nodeId, _NodeState.new);
    state.push(frame, now, windowSize);
    _packets++;
    _sequenceCounter++;

    final DateTime? previous = _lastFrameAt;
    if (previous != null) {
      final double deltaSeconds =
          now.difference(previous).inMicroseconds / Duration.microsecondsPerSecond;
      if (deltaSeconds > 0) {
        // متوسط متحرك لمعدل الإطارات لتجنّب الوميض في الواجهة.
        final double instant = 1 / deltaSeconds;
        _frameRate = _frameRate == 0 ? instant : _frameRate * 0.8 + instant * 0.2;
      }
    }
    _lastFrameAt = now;

    return _buildSensingUpdate(now);
  }

  Map<String, dynamic> _buildSensingUpdate(DateTime now) {
    final List<Map<String, dynamic>> nodes = <Map<String, dynamic>>[];
    double totalMotion = 0;
    double totalVariance = 0;
    double totalBreathingPower = 0;
    double weightedRssi = 0;
    int presenceNodes = 0;
    int personCount = 0;
    double confidenceSum = 0;
    double? breathingBpm;
    double breathingConfidence = 0;
    double dominantFreq = 0;

    for (final MapEntry<int, _NodeState> entry in _nodes.entries) {
      final _NodeState state = entry.value;
      final _NodeMetrics metrics = state.metrics(breathingWindow);
      nodes.add(<String, dynamic>{
        'node_id': entry.key,
        'rssi_dbm': state.lastRssi.toDouble(),
        'position': <double>[0, 0, 0],
        'amplitude': state.lastAmplitudes.length > 64
            ? state.lastAmplitudes.sublist(0, 64)
            : state.lastAmplitudes,
        'subcarrier_count': state.lastAmplitudes.length,
        'frame_rate_hz': double.parse(_frameRate.toStringAsFixed(2)),
        'stale': now.difference(state.lastSeen).inSeconds > 5,
      });

      totalMotion += metrics.motionEnergy;
      totalVariance += metrics.variance;
      totalBreathingPower += metrics.breathingBandPower;
      weightedRssi += state.lastRssi.toDouble();
      if (metrics.presence) {
        presenceNodes++;
        personCount = math.max(personCount, metrics.estimatedPersons);
      }
      confidenceSum += metrics.confidence;
      dominantFreq = math.max(dominantFreq, metrics.breathingFrequencyHz);
      final double? bpm = metrics.breathingBpm;
      if (bpm != null && metrics.confidence >= 0.25) {
        breathingBpm = bpm;
        breathingConfidence = metrics.confidence;
      }
    }

    final int nodeCount = math.max(_nodes.length, 1);
    final double motionBandPower = totalMotion / nodeCount;
    final bool presence = presenceNodes > 0;
    final String motionLevel = !presence
        ? 'absent'
        : (motionBandPower >= 0.35 ? 'present_moving' : 'present_still');

    final Map<String, dynamic> message = <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': now.millisecondsSinceEpoch / 1000.0,
      'source': 'esp32-udp-app',
      'tick': _sequenceCounter,
      'nodes': nodes,
      'features': <String, dynamic>{
        'mean_rssi': weightedRssi / nodeCount,
        'variance': totalVariance / nodeCount,
        'motion_band_power': motionBandPower,
        'breathing_band_power': totalBreathingPower / nodeCount,
        'dominant_freq_hz': dominantFreq,
        'change_points': presence ? 1 : 0,
        'spectral_power': totalVariance / nodeCount,
      },
      'classification': <String, dynamic>{
        'motion_level': motionLevel,
        'presence': presence,
        'confidence': NumUtils.clamp01(confidenceSum / nodeCount),
      },
      // الحقل الدقيق يُحسب على الخادم الرسمي؛ نتركه فارغًا بصدق.
      'signal_field': <String, dynamic>{
        'grid_size': <int>[0, 0, 0],
        'values': <double>[],
      },
      'estimated_persons': personCount,
    };

    if (breathingBpm != null) {
      message['vital_signs'] = <String, dynamic>{
        'breathing_rate_bpm': double.parse(breathingBpm.toStringAsFixed(1)),
        'breathing_confidence': double.parse(breathingConfidence.toStringAsFixed(2)),
        'signal_quality': double.parse(
          NumUtils.clamp01(confidenceSum / nodeCount).toStringAsFixed(2),
        ),
      };
    }

    return message;
  }
}

class _NodeState {
  final List<List<double>> _window = <List<double>>[];
  final List<double> _meanSeries = <double>[];
  final List<DateTime> _meanTimes = <DateTime>[];

  double lastRssi = -70;
  List<double> lastAmplitudes = const <double>[];
  DateTime lastSeen = DateTime.now();

  void push(Esp32CsiFrame frame, DateTime at, int windowSize) {
    lastRssi = frame.rssi.toDouble();
    lastAmplitudes = frame.amplitudes;
    lastSeen = at;

    _window.add(frame.amplitudes);
    if (_window.length > windowSize) _window.removeAt(0);
    _meanSeries.add(frame.meanAmplitude);
    _meanTimes.add(at);
  }

  _NodeMetrics metrics(Duration breathingWindow) {
    if (_window.length < 2) {
      return const _NodeMetrics(
        motionEnergy: 0,
        variance: 0,
        breathingBandPower: 0,
        breathingFrequencyHz: 0,
        presence: false,
        estimatedPersons: 0,
        confidence: 0,
      );
    }

    final List<double> means = _meanSeries;
    final double meanOfMeans =
        means.reduce((double a, double b) => a + b) / means.length;
    if (meanOfMeans <= 0.0001) {
      return const _NodeMetrics(
        motionEnergy: 0,
        variance: 0,
        breathingBandPower: 0,
        breathingFrequencyHz: 0,
        presence: false,
        estimatedPersons: 0,
        confidence: 0,
      );
    }

    double variance = 0;
    for (final double v in means) {
      final double d = v - meanOfMeans;
      variance += d * d;
    }
    variance /= means.length;
    final double normalizedStd = math.sqrt(variance) / meanOfMeans;

    // طاقة الحركة: متوسط التغيّر المطلق بين الإطارات (مُطبّعًا على متوسط السعة).
    double motionEnergy = 0;
    int pairs = 0;
    for (int i = 1; i < _window.length; i++) {
      final List<double> a = _window[i - 1];
      final List<double> b = _window[i];
      final int n = math.min(a.length, b.length);
      if (n == 0) continue;
      double diff = 0;
      double scale = 0;
      for (int k = 0; k < n; k++) {
        diff += (b[k] - a[k]).abs();
        scale += a[k];
      }
      if (scale <= 0.0001) continue;
      motionEnergy += (diff / scale);
      pairs++;
    }
    if (pairs > 0) motionEnergy /= pairs;

    // إزالة الاتجاه: طرح المتوسط المتحرك (نافذة ~3 ثوان) لتسليط الضوء على
    // التذبذب التنفسي (0.1–0.5 هرتز).
    final List<double> detrended = _detrend(means, 15);
    final double breathingPower = detrended.isEmpty
        ? 0
        : detrended
                .map((double v) => v * v)
                .reduce((double a, double b) => a + b) /
            detrended.length;

    final double? bpm = _estimateBreathing(detrended, breathingWindow);

    // تخمين عدد الأشخاص: عتبات تجريبية على تباعد السعة.
    final double presenceScore = NumUtils.clamp01(variance / (meanOfMeans * 0.02));
    final bool presence =
        normalizedStd > 0.02 || motionEnergy > 0.08 || presenceScore > 0.35;
    final int persons = !presence
        ? 0
        : (presenceScore > 0.85 ? 2 : 1);

    return _NodeMetrics(
      motionEnergy: motionEnergy,
      variance: variance,
      breathingBandPower: breathingPower,
      breathingFrequencyHz: bpm == null ? 0 : bpm / 60.0,
      presence: presence,
      estimatedPersons: persons,
      confidence: NumUtils.clamp01(
        math.max(normalizedStd / 0.1, presenceScore) * (means.length < 8 ? 0.6 : 1),
      ),
      breathingBpm: bpm,
    );
  }

  static List<double> _detrend(List<double> values, int window) {
    if (values.length <= window) return const <double>[];
    final List<double> out = <double>[];
    for (int i = window; i < values.length; i++) {
      double sum = 0;
      for (int k = i - window; k < i; k++) {
        sum += values[k];
      }
      out.add(values[i] - sum / window);
    }
    return out;
  }

  double? _estimateBreathing(List<double> detrended, Duration window) {
    if (detrended.length < 10 || _meanTimes.length < 3) return null;
    final Duration span = _meanTimes.last.difference(_meanTimes.first);
    if (span.inSeconds < 8) return null;
    final double seconds = math.min(
      span.inMicroseconds / Duration.microsecondsPerSecond,
      window.inSeconds.toDouble(),
    );
    if (seconds <= 0) return null;

    double rms = 0;
    for (final double v in detrended) {
      rms += v * v;
    }
    rms = math.sqrt(rms / detrended.length);
    if (rms < 0.02) return null;

    // تقاطع صفري مع تبريد بسيط لتجنّب الضجيج.
    int crossings = 0;
    bool? positive;
    for (final double v in detrended) {
      if (v.abs() < rms * 0.15) continue;
      final bool isPositive = v > 0;
      if (positive != null && isPositive != positive) {
        crossings++;
      }
      positive = isPositive;
    }
    if (crossings < 2) return null;

    final double bpm = (crossings / 2) / seconds * 60;
    if (bpm < 6 || bpm > 34) return null;
    return bpm;
  }
}

class _NodeMetrics {
  const _NodeMetrics({
    required this.motionEnergy,
    required this.variance,
    required this.breathingBandPower,
    required this.breathingFrequencyHz,
    required this.presence,
    required this.estimatedPersons,
    required this.confidence,
    this.breathingBpm,
  });

  final double motionEnergy;
  final double variance;
  final double breathingBandPower;
  final double breathingFrequencyHz;
  final bool presence;
  final int estimatedPersons;
  final double confidence;
  final double? breathingBpm;
}
