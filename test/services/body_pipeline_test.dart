import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/connection_settings.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/domain/monitoring/posture_estimator.dart';
import 'package:ruview_wifi/domain/twin/twin_engine.dart';
import 'package:ruview_wifi/domain/twin/twin_state.dart';

/// سلسلة كاملة من المقبس إلى المجسّم: بوابة حقيقية → مستودع → تقدير وضعية →
/// محرّك التوأم. هذا الاختبار يجيب على السؤال: «لماذا لا تظهر الأجسام؟».

const List<String> _jointNames = <String>[
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

/// هيكل واقف واقعي (نفس نسب هيكل بوابة RuView المرجعية).
const List<List<double>> _standing = <List<double>>[
  <double>[0.5, 0.10],
  <double>[0.47, 0.08],
  <double>[0.53, 0.08],
  <double>[0.46, 0.09],
  <double>[0.54, 0.09],
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

Map<String, dynamic> _frameWithPose(int tick) {
  final List<Map<String, dynamic>> keypoints = <Map<String, dynamic>>[
    for (int i = 0; i < _jointNames.length; i++)
      <String, dynamic>{
        'name': _jointNames[i],
        'x': _standing[i][0],
        'y': _standing[i][1],
        'z': 0,
        'confidence': 0.9,
      },
  ];
  return <String, dynamic>{
    'type': 'sensing_update',
    'tick': tick,
    'features': <String, dynamic>{'motion_band_power': 0.8, 'variance': 1.5},
    'classification': <String, dynamic>{
      'motion_level': 'present_moving',
      'presence': true,
      'confidence': 0.9,
    },
    'persons': <dynamic>[
      <String, dynamic>{
        'id': 1,
        'confidence': 0.92,
        'pose': 'walking',
        'keypoints': keypoints,
      },
    ],
  };
}

Map<String, dynamic> _presenceOnlyFrame(int tick) => <String, dynamic>{
      'type': 'sensing_update',
      'tick': tick,
      'features': <String, dynamic>{'motion_band_power': 0.6, 'variance': 1.1},
      'classification': <String, dynamic>{
        'motion_level': 'present_still',
        'presence': true,
        'confidence': 0.8,
      },
    };

/// بوابة تُبثّ إطاراتها عبر WebSocket على /ws/sensing.
Future<HttpServer> startGateway(Map<String, dynamic> Function(int tick) frame) async {
  final HttpServer server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    if (request.uri.path == '/health') {
      request.response
        ..statusCode = 200
        ..write('{"service":"ruview-gateway","sensing_path":"/ws/sensing"}');
      await request.response.close();
      return;
    }
    if (request.uri.path == '/ws/sensing' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      int tick = 0;
      final Timer timer = Timer.periodic(
        const Duration(milliseconds: 25),
        (Timer t) {
          if (tick > 12) {
            t.cancel();
            unawaited(socket.close());
            return;
          }
          socket.add(jsonEncode(frame(tick++)));
        },
      );
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
}

Future<SensingFrame> firstFrameFrom(HttpServer server) async {
  final SensingRepository repository = SensingRepository();
  final Completer<SensingFrame> completer = Completer<SensingFrame>();
  final StreamSubscription<SensingFrame> sub =
      repository.frames.listen((SensingFrame frame) {
    if (!completer.isCompleted) completer.complete(frame);
  });
  await repository.connect(
    ConnectionSettings(
      host: '127.0.0.1',
      port: server.port,
      transport: TransportKind.webSocket,
    ),
  );
  final SensingFrame frame =
      await completer.future.timeout(const Duration(seconds: 8));
  await sub.cancel();
  await repository.dispose();
  return frame;
}

void main() {
  test('بوابة ترسل مفاصل: المجسّم يُبنى من مفاصلها مباشرة', () async {
    final HttpServer server = await startGateway(_frameWithPose);
    addTearDown(() => server.close(force: true));

    final SensingFrame frame = await firstFrameFrom(server);
    expect(frame.persons, isNotEmpty);
    expect(frame.persons.first.keypoints.length, greaterThanOrEqualTo(17));

    final PostureEstimate estimate = PostureEstimator.estimate(frame);
    expect(estimate.keypoints, isNotEmpty);

    final TwinState state = TwinEngine().update(
      frame: frame,
      posture: estimate.posture,
      keypoints: estimate.keypoints,
    );

    expect(state.hasBody, isTrue);
    expect(state.hasMesh, isTrue);
    expect(state.poseInferred, isFalse);
  });

  test('بوابة ترسل حضورًا بلا مفاصل: المجسّم يُبنى مستنتجًا', () async {
    final HttpServer server = await startGateway(_presenceOnlyFrame);
    addTearDown(() => server.close(force: true));

    final SensingFrame frame = await firstFrameFrom(server);
    expect(frame.hasPresence, isTrue);
    expect(frame.persons, isEmpty);

    final PostureEstimate estimate = PostureEstimator.estimate(frame);
    expect(estimate.keypoints, isEmpty);

    final TwinState state = TwinEngine().update(
      frame: frame,
      posture: estimate.posture,
      keypoints: estimate.keypoints,
    );

    expect(
      state.hasBody,
      isTrue,
      reason: 'هذه هي الحالة التي كانت تُظهر «لا أجسام» بلا سبب',
    );
    expect(state.hasMesh, isTrue);
    expect(state.poseInferred, isTrue);
  });
}
