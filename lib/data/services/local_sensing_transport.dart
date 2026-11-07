import 'dart:async';
import 'dart:math' as math;

import '../models/connection_settings.dart';
import '../models/connection_status.dart';
import 'sensing_transport.dart';

/// مصدر استشعار داخلي (محاكاة) يعمل بالكامل داخل التطبيق — بلا شبكة ولا بوابة.
///
/// الفكرة: التطبيق لا يبقى «ميتًا» حين لا توجد بوابة RuView في الشبكة. هذا
/// النقل يُنتج إطارات `sensing_update` بنفس بنية الرسائل الرسمية (عُقد، ميزات
/// CSI، تصنيف، أشخاص بمفاصل COCO الـ17، علامات حيوية)، فتمرّ عبر نفس خط
/// المعالجة الحقيقي: المستودع ← ViewModels ← الواجهة.
///
/// **حدّ صريح:** هذه البيانات مولّدة رياضيًا وليست قياسًا للموجات. الواجهة
/// تُعلن ذلك في كل مكان يظهر فيه وضع المحاكاة، ولا يجوز اعتباره استشعارًا.
class LocalSensingTransport implements SensingTransport {
  LocalSensingTransport({
    this.frameInterval = const Duration(milliseconds: 250),
    int seed = 17,
  }) : _random = math.Random(seed);

  /// معدل البث (4 إطارات/ثانية افتراضيًا — قريب من بوابات RuView الحقيقية).
  final Duration frameInterval;

  final math.Random _random;
  final StreamController<TransportEvent> _controller =
      StreamController<TransportEvent>.broadcast();

  Timer? _timer;
  bool _active = false;
  int _tick = 0;

  /// أسماء المفاصل السبعة عشر (ترتيب COCO) — نفس ما تتوقعه بوابة RuView.
  static const List<String> jointNames = <String>[
    'nose',
    'left_eye',
    'right_eye',
    'left_ear',
    'right_ear',
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

  /// وضعية الوقوف الأساسية (إحداثيات مُطبّعة 0..1، المحور y للأسفل).
  static const List<List<double>> _restPose = <List<double>>[
    <double>[0.500, 0.090],
    <double>[0.485, 0.075],
    <double>[0.515, 0.075],
    <double>[0.465, 0.085],
    <double>[0.535, 0.085],
    <double>[0.435, 0.200],
    <double>[0.565, 0.200],
    <double>[0.415, 0.330],
    <double>[0.585, 0.330],
    <double>[0.400, 0.450],
    <double>[0.600, 0.450],
    <double>[0.465, 0.520],
    <double>[0.535, 0.520],
    <double>[0.462, 0.720],
    <double>[0.538, 0.720],
    <double>[0.460, 0.920],
    <double>[0.540, 0.920],
  ];

  /// مفاصل الأطراف التي تتأرجح أثناء المشي (الفخذ/الركبة/الكاحل/الرسغ).
  static const Set<int> _limbJoints = <int>{7, 8, 9, 10, 13, 14, 15, 16};

  @override
  Stream<TransportEvent> get events => _controller.stream;

  @override
  bool get isActive => _active;

  @override
  Future<void> connect(ConnectionSettings settings) async {
    if (_active) return;
    _active = true;
    _tick = 0;
    _emit(TransportEvent.connected(message: 'محاكاة داخلية — بلا شبكة'));
    _emitFrame();
    _timer = Timer.periodic(frameInterval, (Timer _) => _emitFrame());
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    if (!_active) return;
    _active = false;
    _emit(TransportEvent.disconnected(message: 'تم إيقاف المحاكاة'));
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _active = false;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  // ── توليد الإطارات ─────────────────────────────────────────────────────

  void _emitFrame() {
    if (_controller.isClosed) return;
    _controller.add(TransportEvent.data(_buildFrame()));
    _tick++;
  }

  void _emit(TransportEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  /// المشهد المتكرر: 44 ثانية = 40 ثانية حضور + 4 ثوانٍ غياب، وداخل الحضور
  /// دورة 22 ثانية (10 ثوانٍ حركة ثم 12 ثانية سكون).
  Map<String, dynamic> _buildFrame() {
    final double seconds =
        _tick * (frameInterval.inMilliseconds / 1000.0);
    final double cycle = seconds % 44;
    final bool presence = cycle < 40;
    final bool moving = presence && (seconds % 22) < 10;

    final double breathBpm =
        15.0 + 1.4 * math.sin(seconds / 11.0) + _noise(0.35);
    final double heartBpm =
        69.0 + 3.6 * math.sin(seconds / 17.0) + _noise(1.1);

    final double rssi = -47.0 + 2.6 * math.sin(seconds / 7.0) + _noise(0.8);
    final double motionPower = presence
        ? (moving
            ? 1.15 + 0.22 * math.sin(seconds * 1.7) + _noise(0.08)
            : 0.16 + 0.05 * math.sin(seconds * 0.6) + _noise(0.02))
        : 0.03;

    final double personX = 2.5 + 0.55 * math.sin(seconds / 6.0);
    final double personZ = 2.0 + 0.40 * math.cos(seconds / 8.0);

    return <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'source': 'محاكاة داخلية',
      'tick': _tick,
      'nodes': _nodes(rssi),
      'features': <String, dynamic>{
        'mean_rssi': _round(rssi),
        'variance': _round(presence ? 1.4 + motionPower * 0.9 : 0.35),
        'motion_band_power': _round(motionPower),
        'breathing_band_power':
            _round(presence ? 0.22 + 0.03 * math.sin(seconds) : 0.01),
        'dominant_freq_hz':
            _round(moving ? 1.55 + _noise(0.12) : 0.27 + _noise(0.02)),
        'change_points': moving ? 7 : (presence ? 1 : 0),
        'spectral_power': _round(presence ? 0.62 : 0.05),
      },
      'classification': <String, dynamic>{
        'motion_level': !presence
            ? 'absent'
            : (moving ? 'present_moving' : 'present_still'),
        'presence': presence,
        'confidence': _round(presence ? 0.88 + _noise(0.04) : 0.42),
      },
      'vital_signs': <String, dynamic>{
        'breathing_rate_bpm': presence ? _round(breathBpm) : 0.0,
        'heart_rate_bpm': presence ? _round(heartBpm) : 0.0,
        'breathing_confidence': presence ? 0.83 : 0.0,
        'heartbeat_confidence': presence ? 0.71 : 0.0,
        'signal_quality': _round(0.5 + 0.5 * ((rssi + 90) / 55).clamp(0.0, 1.0)),
      },
      'persons': presence ? _persons(moving, seconds, personX, personZ) : <Object>[],
      'estimated_persons': presence ? 1 : 0,
      'signal_field': _signalField(presence, personX, personZ),
    };
  }

  List<Map<String, dynamic>> _nodes(double rssi) {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'node_id': 1,
        'rssi_dbm': _round(rssi),
        'position': <double>[0.0, 1.2, 0.0],
        'subcarrier_count': 32,
        'amplitude': _amplitudes(rssi, 1),
        'frame_rate_hz': 4.0,
        'stale': false,
      },
      <String, dynamic>{
        'node_id': 2,
        'rssi_dbm': _round(rssi - 5.5 + _noise(0.6)),
        'position': <double>[5.0, 1.2, 4.0],
        'subcarrier_count': 32,
        'amplitude': _amplitudes(rssi - 5.5, 2),
        'frame_rate_hz': 4.0,
        'stale': false,
      },
    ];
  }

  List<double> _amplitudes(double rssi, int offset) {
    final double base = (rssi + 95) / 60;
    return <double>[
      for (int i = 0; i < 32; i++)
        _round(
          (base + 0.18 * math.sin(i / 3.1 + _tick / 9.0 + offset))
              .clamp(0.0, 1.5)
              .toDouble(),
        ),
    ];
  }

  List<Map<String, dynamic>> _persons(
    bool moving,
    double seconds,
    double x,
    double z,
  ) {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'confidence': _round(0.9 + _noise(0.03)),
        'zone': 'living',
        'position': <double>[_round(x), 0.0, _round(z)],
        'motion_score': _round(moving ? 62.0 + _noise(6.0) : 13.0 + _noise(3.0)),
        'pose': moving ? 'walking' : 'standing',
        'keypoints': _keypoints(moving, seconds),
      },
    ];
  }

  List<Map<String, dynamic>> _keypoints(bool moving, double seconds) {
    final double sway =
        math.sin(seconds * (moving ? 2.1 : 0.85)) * (moving ? 0.022 : 0.006);
    final double stride = moving ? math.sin(seconds * 2.4) * 0.028 : 0.0;
    final double swing = moving ? math.sin(seconds * 2.4 + math.pi) * 0.030 : 0.0;
    final double breath = math.sin(seconds * 1.6) * 0.004;

    final List<Map<String, dynamic>> joints = <Map<String, dynamic>>[];
    for (int i = 0; i < _restPose.length; i++) {
      final double baseX = _restPose[i][0];
      final double baseY = _restPose[i][1];
      double dx = sway * (1.15 - baseY);
      double dy = 0;
      if (_limbJoints.contains(i)) {
        final bool leftSide = baseX < 0.5;
        final double amount = leftSide ? stride : -stride;
        dx += amount;
        // الرسغان يتأرجحان بعكس اتجاه الساق.
        if (i == 9 || i == 10) dx += leftSide ? swing : -swing;
      }
      if (i == 5 || i == 6) dy -= breath;
      joints.add(<String, dynamic>{
        'name': jointNames[i],
        'x': _round((baseX + dx).clamp(0.02, 0.98).toDouble()),
        'y': _round((baseY + dy).clamp(0.02, 0.98).toDouble()),
        'z': _round(0.02 * math.sin(seconds * 1.2 + i / 4)),
        'confidence': _round(0.86 + _noise(0.05)),
      });
    }
    return joints;
  }

  Map<String, dynamic> _signalField(
    bool presence,
    double personX,
    double personZ,
  ) {
    const int size = 8;
    final List<double> values = <double>[];
    for (int ix = 0; ix < size; ix++) {
      for (int iz = 0; iz < size; iz++) {
        final double cx = (ix + 0.5) * 0.625;
        final double cz = (iz + 0.5) * 0.5;
        final double d2 =
            math.pow(cx - personX, 2).toDouble() +
                math.pow(cz - personZ, 2).toDouble();
        final double peak = presence ? math.exp(-d2 / 0.9) : 0.0;
        values.add(_round(peak * 0.85 + _noise(0.03)));
      }
    }
    return <String, dynamic>{
      'grid_size': <int>[size, 1, size],
      'values': values,
    };
  }

  double _noise(double amplitude) => (_random.nextDouble() * 2 - 1) * amplitude;

  double _round(double value) => (value * 1000).roundToDouble() / 1000;
}
