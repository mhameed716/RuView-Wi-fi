import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/connection_settings.dart';
import 'package:ruview_wifi/data/models/connection_status.dart';
import 'package:ruview_wifi/data/services/lan_scanner.dart';
import 'package:ruview_wifi/data/services/websocket_sensing_transport.dart';

/// بوابات حقيقية على مقابس حقيقية داخل العملية — تحقّق فعلي لا محاكاة.

Map<String, dynamic> sensingFrame({int tick = 1}) => <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': 1767225600,
      'tick': tick,
      'features': <String, dynamic>{
        'motion_band_power': 0.7,
        'dominant_freq_hz': 1.1,
        'variance': 1.4,
      },
      'classification': <String, dynamic>{
        'motion_level': 'present_moving',
        'presence': true,
        'confidence': 0.9,
      },
    };

const String healthJson =
    '{"status":"ok","service":"ruview-gateway","sensing_path":"/ws/sensing"}';

/// بوابة تخدم WebSocket على [wsPath] فقط.
Future<HttpServer> startWebSocketGateway({
  String wsPath = '/ws/sensing',
  int frames = 3,
}) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    final String path = request.uri.path;
    if (path == '/health') {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(healthJson);
      await request.response.close();
      return;
    }
    if (path == wsPath && WebSocketTransformer.isUpgradeRequest(request)) {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      for (int i = 0; i < frames; i++) {
        socket.add(jsonEncode(sensingFrame(tick: i)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
}

/// بوابة ترفض ترقية WebSocket وتقدّم REST فقط.
Future<HttpServer> startRestOnlyGateway({
  bool serveRest = true,
  bool serveHtml = false,
}) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    final String path = request.uri.path;
    // خادم ويب عادي لا يعرف /health أصلًا: يخدم صفحته لكل مسار.
    if (serveHtml) {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html><title>RuView Wi-Fi</title><body>sensing</body></html>');
      await request.response.close();
      return;
    }
    if (path == '/health') {
      request.response
        ..statusCode = 200
        ..write(healthJson);
      await request.response.close();
      return;
    }
    if (serveRest && path == '/api/v1/sensing/latest') {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(sensingFrame(tick: 5)));
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
}

ConnectionSettings settingsFor(int port) => ConnectionSettings(
      host: '127.0.0.1',
      port: port,
      transport: TransportKind.webSocket,
    );

Future<List<TransportEvent>> collectUntil(
  Stream<TransportEvent> events,
  bool Function(List<TransportEvent> events) done, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final List<TransportEvent> collected = <TransportEvent>[];
  final Completer<void> completer = Completer<void>();
  late final StreamSubscription<TransportEvent> sub;
  sub = events.listen((TransportEvent event) {
    collected.add(event);
    if (!completer.isCompleted && done(collected)) completer.complete();
  });
  await completer.future.timeout(timeout, onTimeout: () => collected);
  await sub.cancel();
  return collected;
}

void main() {
  group('النقل: WebSocket حقيقي', () {
    test('يتصل بـ /ws/sensing ويستقبل إطارات sensing_update', () async {
      final HttpServer server = await startWebSocketGateway();
      final WebSocketSensingTransport transport = WebSocketSensingTransport(
        connectTimeout: const Duration(seconds: 3),
      );
      addTearDown(() async {
        await transport.dispose();
        await server.close(force: true);
      });

      final Future<List<TransportEvent>> collected = collectUntil(
        transport.events,
        (List<TransportEvent> list) =>
            list.where((TransportEvent e) => e.kind == TransportEventKind.frame).length >= 2,
      );
      await transport.connect(settingsFor(server.port));
      final List<TransportEvent> events = await collected;

      expect(
        events.any((TransportEvent e) => e.kind == TransportEventKind.connected),
        isTrue,
      );
      final List<TransportEvent> frames = events
          .where((TransportEvent e) => e.kind == TransportEventKind.frame)
          .toList();
      expect(frames.length, greaterThanOrEqualTo(2));
      final Object? payload = frames.first.frame;
      expect(payload, isA<Map<String, dynamic>>());
      expect((payload! as Map<String, dynamic>)['type'], 'sensing_update');
    });

    test('ينتقل إلى مسار الوضعية /api/v1/stream/pose عند غياب /ws/sensing',
        () async {
      final HttpServer server =
          await startWebSocketGateway(wsPath: '/api/v1/stream/pose');
      final WebSocketSensingTransport transport = WebSocketSensingTransport(
        connectTimeout: const Duration(seconds: 3),
      );
      addTearDown(() async {
        await transport.dispose();
        await server.close(force: true);
      });

      final Future<List<TransportEvent>> collected = collectUntil(
        transport.events,
        (List<TransportEvent> list) => list
            .any((TransportEvent e) => e.kind == TransportEventKind.frame),
      );
      await transport.connect(settingsFor(server.port));
      final List<TransportEvent> events = await collected;

      expect(
        events.any((TransportEvent e) => e.kind == TransportEventKind.frame),
        isTrue,
        reason: 'المسار البديل لم يُجرَّب',
      );
    });
  });

  group('النقل: بديل REST', () {
    test('خادم يرفض WebSocket: يتحوّل تلقائيًا إلى REST ويستقبل إطارات',
        () async {
      final HttpServer server = await startRestOnlyGateway();
      final WebSocketSensingTransport transport = WebSocketSensingTransport(
        connectTimeout: const Duration(seconds: 2),
        restTimeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 120),
      );
      addTearDown(() async {
        await transport.dispose();
        await server.close(force: true);
      });

      final Future<List<TransportEvent>> collected = collectUntil(
        transport.events,
        (List<TransportEvent> list) =>
            list.where((TransportEvent e) => e.kind == TransportEventKind.frame).length >= 2,
        timeout: const Duration(seconds: 8),
      );
      await transport.connect(settingsFor(server.port));
      final List<TransportEvent> events = await collected;

      expect(transport.usesRestFallback, isTrue);
      final List<TransportEvent> frames = events
          .where((TransportEvent e) => e.kind == TransportEventKind.frame)
          .toList();
      expect(frames.length, greaterThanOrEqualTo(2));
      final TransportEvent connected = events.firstWhere(
        (TransportEvent e) => e.kind == TransportEventKind.connected,
        orElse: () => TransportEvent.failed('لا اتصال'),
      );
      expect(connected.message ?? '', contains('REST'));
    });

    test('خادم HTTP عادي (صفحة HTML): رسالة تشخيص صريحة بلا إعادة محاولة',
        () async {
      final HttpServer server =
          await startRestOnlyGateway(serveRest: false, serveHtml: true);
      final WebSocketSensingTransport transport = WebSocketSensingTransport(
        connectTimeout: const Duration(seconds: 2),
        restTimeout: const Duration(seconds: 2),
      );
      addTearDown(() async {
        await transport.dispose();
        await server.close(force: true);
      });

      final Future<List<TransportEvent>> collected = collectUntil(
        transport.events,
        (List<TransportEvent> list) =>
            list.any((TransportEvent e) => e.kind == TransportEventKind.error),
        timeout: const Duration(seconds: 8),
      );
      await transport.connect(settingsFor(server.port));
      final List<TransportEvent> events = await collected;

      final TransportEvent error = events.firstWhere(
        (TransportEvent e) => e.kind == TransportEventKind.error,
      );
      expect(error.message, isNotNull);
      expect(
        error.message!,
        anyOf(contains('HTTP 200'), contains('404'), contains('ليس منفذ')),
        reason: 'الرسالة يجب أن تشرح سبب فشل الترقية',
      );
      expect(transport.usesRestFallback, isFalse);
    });
  });

  group('الماسح الحقيقي على ماسح ضوئي حقيقي', () {
    test('يكتشف بوابة RuView عبر TCP ويعطيها أعلى درجة', () async {
      final HttpServer server = await startWebSocketGateway();
      final LanScanner scanner = LanScanner(
        ports: <int>[server.port],
        useBroadcast: false,
        connectTimeout: const Duration(milliseconds: 400),
        maxScanDuration: const Duration(seconds: 8),
      );
      addTearDown(() => server.close(force: true));

      const NetworkContext context = NetworkContext(
        localAddresses: <String>['127.0.0.1'],
        prefixes: <String>['127.0.0'],
        fingerprint: 'loopback',
      );

      final List<LanCandidate> found = await scanner.scan(
        context: context,
        savedHosts: <String>{'127.0.0.1'},
      );

      expect(found, isNotEmpty);
      final LanCandidate candidate = found.first;
      expect(candidate.host, '127.0.0.1');
      expect(candidate.port, server.port);
      expect(candidate.looksLikeRuView, isTrue);
      expect(candidate.isSaved, isTrue);
    });

    test('صفحة ويب عادية (HTML) لا تُصنَّف بوابة RuView', () async {
      final HttpServer server =
          await startRestOnlyGateway(serveRest: false, serveHtml: true);
      final LanScanner scanner = LanScanner(
        ports: <int>[server.port],
        useBroadcast: false,
        connectTimeout: const Duration(milliseconds: 400),
      );
      addTearDown(() => server.close(force: true));

      final LanCandidate? candidate = await scanner.probe(
        '127.0.0.1',
        server.port,
      );

      expect(candidate, isNotNull, reason: 'المنفذ مفتوح فيجب أن يبقى مرشّحًا');
      expect(
        candidate!.looksLikeRuView,
        isFalse,
        reason: 'ردّ 200 من صفحة HTML لا يعني بوابة RuView',
      );
    });
  });
}
