import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/connection_settings.dart';
import 'package:ruview_wifi/data/services/lan_scanner.dart';

void main() {
  group('NetworkContext', () {
    test('يستخرج البادئة والبوابة من عنوان محلي', () {
      final NetworkContext context =
          NetworkContext.fromAddresses(<String>['192.168.1.42']);

      expect(context.isConnected, isTrue);
      expect(context.prefix, '192.168.1');
      expect(context.gatewayHost, '192.168.1.1');
      expect(context.gatewayHosts, <String>['192.168.1.1']);
      expect(context.fingerprint, '192.168.1');
      expect(context.label, contains('192.168.1.42'));
    });

    test('يتجاهل العناوين العامة والاسترجاع الذاتي', () {
      final NetworkContext context = NetworkContext.fromAddresses(<String>[
        '127.0.0.1',
        '8.8.8.8',
        '169.254.10.5',
      ]);

      expect(context.isConnected, isFalse);
      expect(context.fingerprint, NetworkContext.offline.fingerprint);
    });

    test('يدعم نطاقات 10.x و172.16-31.x', () {
      expect(
        NetworkContext.fromAddresses(<String>['10.0.5.9']).prefix,
        '10.0.5',
      );
      expect(
        NetworkContext.fromAddresses(<String>['172.20.3.4']).gatewayHost,
        '172.20.3.1',
      );
    });

    test('يدعم نقطة اتصال آيفون 172.20.10.x وأندرويد 192.168.43.x', () {
      final NetworkContext iphone =
          NetworkContext.fromAddresses(<String>['172.20.10.3']);
      final NetworkContext android =
          NetworkContext.fromAddresses(<String>['192.168.43.129']);

      expect(iphone.gatewayHost, '172.20.10.1');
      expect(android.gatewayHost, '192.168.43.1');
    });

    test('يغطّي واجهتين معًا (واي فاي + نقطة اتصال)', () {
      final NetworkContext context = NetworkContext.fromAddresses(<String>[
        '192.168.1.42',
        '192.168.43.1',
        '192.168.1.42',
      ]);

      expect(context.localAddresses, <String>['192.168.1.42', '192.168.43.1']);
      expect(context.prefixes, <String>['192.168.1', '192.168.43']);
      expect(
        context.gatewayHosts,
        <String>['192.168.1.1', '192.168.43.1'],
      );
      expect(context.label, contains('+1'));
      // البصمة لا تتأثر بترتيب العناوين وإنما بمجموعة الشبكات.
      expect(
        NetworkContext.fromAddresses(<String>['192.168.43.1', '192.168.1.42'])
            .fingerprint,
        context.fingerprint,
      );
    });

    test('تغيير الشبكة يغيّر البصمة', () {
      final String home =
          NetworkContext.fromAddresses(<String>['192.168.1.5']).fingerprint;
      final String hotspot =
          NetworkContext.fromAddresses(<String>['192.168.43.5']).fingerprint;

      expect(home, isNot(hotspot));
    });

    test('يقبل نطاق CGNAT المستخدم في أنفاق الشبكات', () {
      expect(
        NetworkContext.fromAddresses(<String>['100.101.102.103']).isConnected,
        isTrue,
      );
    });
  });

  group('LanScanner.hostsFor', () {
    test('يبدأ بآخر اتصال ناجح ثم بوابة الشبكة', () {
      final NetworkContext context =
          NetworkContext.fromAddresses(<String>['10.0.0.7']);
      final List<String> hosts = LanScanner.hostsFor(
        context,
        extra: <String>{'10.0.0.9'},
      );

      expect(hosts.first, '10.0.0.9');
      expect(hosts[1], '10.0.0.1');
      expect(hosts, contains('10.0.0.7'));
      expect(hosts.length, lessThan(20));
    });

    test('يشمل بوابات كل الواجهات معًا', () {
      final NetworkContext context = NetworkContext.fromAddresses(<String>[
        '192.168.1.42',
        '192.168.43.1',
      ]);
      final List<String> hosts = LanScanner.hostsFor(context);

      expect(hosts, contains('192.168.1.1'));
      expect(hosts, contains('192.168.43.1'));
      expect(hosts, contains('ruview.local'));
    });

    test('المسح العميق يغطّي كل عناوين /24', () {
      final NetworkContext context =
          NetworkContext.fromAddresses(<String>['192.168.0.10']);
      final List<String> hosts = LanScanner.hostsFor(context, deep: true);

      expect(hosts.length, greaterThanOrEqualTo(254));
      expect(hosts, contains('192.168.0.1'));
      expect(hosts, contains('192.168.0.254'));
    });

    test('المسح العميق مع واجهتين يغطّي الشبكتين', () {
      final NetworkContext context = NetworkContext.fromAddresses(<String>[
        '192.168.1.42',
        '172.20.10.2',
      ]);
      final List<String> hosts = LanScanner.hostsFor(context, deep: true);

      expect(hosts, contains('192.168.1.77'));
      expect(hosts, contains('172.20.10.77'));
      expect(hosts.length, greaterThanOrEqualTo(508));
    });

    test('بلا شبكة لا عناوين للمسح', () {
      expect(
        LanScanner.hostsFor(NetworkContext.offline, deep: true),
        isEmpty,
      );
    });
  });

  group('اكتشاف البثّ (UDP 5005)', () {
    test('يقرأ ردّ البوابة ويستخرج المضيف والمنفذ', () {
      final LanCandidate? candidate = LanScanner.candidateFromDiscovery(
        '{"type":"ruview_gateway","host":"192.168.43.1","port":3000}',
        '192.168.43.1',
      );

      expect(candidate, isNotNull);
      expect(candidate!.host, '192.168.43.1');
      expect(candidate.port, 3000);
      expect(candidate.looksLikeRuView, isTrue);
      expect(candidate.transport, TransportKind.webSocket);
      expect(candidate.sourceLabel, 'خادم RuView');
    });

    test('يستخدم عنوان المرسل عند غياب host في الردّ', () {
      final LanCandidate? candidate = LanScanner.candidateFromDiscovery(
        '{"type":"ruview_gateway","port":8765}',
        '10.0.0.1',
      );

      expect(candidate!.host, '10.0.0.1');
      expect(candidate.port, 8765);
    });

    test('يقبل ردًّا نصيًا يذكر RuView بلا JSON', () {
      final LanCandidate? candidate = LanScanner.candidateFromDiscovery(
        'RUVIEW-GATEWAY',
        '192.168.1.1',
      );

      expect(candidate!.host, '192.168.1.1');
      expect(candidate.port, 3000);
    });

    test('يتجاهل الردود غير المتعلقة أو المنافذ غير الصالحة', () {
      expect(LanScanner.candidateFromDiscovery('hello', '1.2.3.4'), isNull);
      expect(LanScanner.candidateFromDiscovery('', '1.2.3.4'), isNull);
      expect(
        LanScanner.candidateFromDiscovery(
          '{"type":"ruview_gateway","port":99999}',
          '1.2.3.4',
        ),
        isNull,
      );
    });

    test('ردّ البثّ يتقدّم على بوابة بمنفذ مفتوح بلا هوية RuView', () {
      final List<LanCandidate> ranked = LanScanner.ranked(<LanCandidate>[
        const LanCandidate(
          host: '192.168.1.1',
          port: 8765,
          latencyMs: 2,
          isGateway: true,
        ),
        const LanCandidate(
          host: '192.168.1.50',
          port: 3000,
          looksLikeRuView: true,
          source: 'بثّ',
        ),
      ]);

      expect(ranked.first.host, '192.168.1.50');
      expect(ranked.first.sourceLabel, 'خادم RuView');
    });
  });

  group('ترتيب المرشّحين', () {
    test('خادم RuView المحفوظ يتقدّم على منفذ مفتوح عادي', () {
      final List<LanCandidate> ranked = LanScanner.ranked(<LanCandidate>[
        const LanCandidate(host: '192.168.1.5', port: 8080, latencyMs: 12),
        const LanCandidate(
          host: '192.168.1.9',
          port: 8765,
          latencyMs: 40,
          looksLikeRuView: true,
          isSaved: true,
        ),
        const LanCandidate(
          host: '192.168.1.1',
          port: 3000,
          latencyMs: 5,
          isGateway: true,
        ),
      ]);

      expect(ranked.first.host, '192.168.1.9');
      expect(ranked.first.looksLikeRuView, isTrue);
      expect(ranked.first.sourceLabel, 'خادم RuView');
      expect(ranked.last.host, '192.168.1.5');
    });

    test('عند تساوي البصمة يفوز الأسرع', () {
      final List<LanCandidate> ranked = LanScanner.ranked(<LanCandidate>[
        const LanCandidate(
          host: '192.168.1.20',
          port: 8765,
          latencyMs: 90,
          looksLikeRuView: true,
        ),
        const LanCandidate(
          host: '192.168.1.21',
          port: 8765,
          latencyMs: 8,
          looksLikeRuView: true,
        ),
      ]);

      expect(ranked.first.host, '192.168.1.21');
    });

    test('زمن الاستجابة العالي لا يقلب الترتيب أكثر من الحد', () {
      const LanCandidate slow = LanCandidate(
        host: '192.168.1.30',
        port: 8765,
        latencyMs: 5000,
        looksLikeRuView: true,
      );
      const LanCandidate fast = LanCandidate(
        host: '192.168.1.31',
        port: 8765,
        latencyMs: 1,
        looksLikeRuView: true,
      );

      expect(slow.score, 116 - 20);
      expect(fast.score, greaterThan(slow.score));
    });
  });

  group('LanCandidate', () {
    test('يحوّل إلى إعدادات اتصال كاملة', () {
      const LanCandidate candidate = LanCandidate(
        host: '192.168.1.30',
        port: 8765,
        latencyMs: 20,
        looksLikeRuView: true,
      );
      final ConnectionSettings settings = candidate.toSettings(
        authToken: 'token',
        secure: true,
      );

      expect(settings.host, '192.168.1.30');
      expect(settings.port, 8765);
      expect(settings.transport, TransportKind.webSocket);
      expect(settings.authToken, 'token');
      expect(settings.secure, isTrue);
      expect(settings.isValid, isTrue);
    });

    test('JSON ذهاب وعودة يحفظ كل الحقول', () {
      const LanCandidate candidate = LanCandidate(
        host: '10.1.2.3',
        port: 3001,
        latencyMs: 33,
        looksLikeRuView: true,
        isSaved: true,
        source: 'محفوظ',
      );

      final LanCandidate restored = LanCandidate.fromJson(candidate.toJson());
      expect(restored.host, candidate.host);
      expect(restored.port, candidate.port);
      expect(restored.looksLikeRuView, isTrue);
      expect(restored.score, candidate.score);
    });

    test('JSON تالف لا يُسقط التطبيق', () {
      expect(LanCandidate.fromJson(null).port, 0);
      expect(LanCandidate.fromJson(<String, dynamic>{}).port, 8765);
      expect(
        LanCandidate.fromJson(<String, dynamic>{'transport': 12}).transport,
        TransportKind.webSocket,
      );
    });
  });

  group('NetworkWatcher', () {
    test('ينبّه عند تغيّر الشبكة فقط', () async {
      final List<bool> changes = <bool>[];
      final List<String> fingerprints = <String>[];
      NetworkContext current =
          NetworkContext.fromAddresses(<String>['192.168.1.9']);

      final NetworkWatcher watcher = NetworkWatcher(
        interval: const Duration(milliseconds: 30),
        detector: () async => current,
      );
      watcher.start((NetworkContext context, bool changed) {
        changes.add(changed);
        fingerprints.add(context.fingerprint);
      });

      await Future<void>.delayed(const Duration(milliseconds: 40));
      current = NetworkContext.fromAddresses(<String>['192.168.43.5']);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      watcher.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(changes.length, greaterThanOrEqualTo(2));
      // أول نبضة: من «بلا شبكة» إلى شبكة، ثم نبضة عند الانتقال لنقطة الاتصال.
      expect(changes.first, isTrue);
      expect(fingerprints, contains('192.168.43'));
      expect(changes.where((bool value) => value).length, 2);
    });
  });

  group('التحقق القاطع عبر WebSocket (فحص حقيقي)', () {
    test('يقبل منفذًا يُكمل المصافحة ويرسل إطار sensing_update', () async {
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        try {
          if (!WebSocketTransformer.isUpgradeRequest(request)) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }
          final WebSocket socket = await WebSocketTransformer.upgrade(request);
          socket.add(jsonEncode(<String, dynamic>{
            'type': 'sensing_update',
            'tick': 1,
            'classification': <String, dynamic>{
              'presence': true,
              'motion_level': 'present_still',
            },
            'features': <String, dynamic>{'motion_band_power': 0.4},
          }));
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await socket.close();
        } catch (_) {
          // العميل أغلق مبكرًا — لا يهم في هذا الاختبار.
        }
      });

      final LanScanner scanner = LanScanner(
        useBroadcast: false,
        verifyTimeout: const Duration(milliseconds: 1200),
      );
      final bool verified =
          await scanner.verifySensing('127.0.0.1', server.port);

      expect(verified, isTrue);
      await server.close(force: true);
    });

    test('يرفض خادم HTTP عاديًا يفتح المنفذ بلا استشعار', () async {
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        request.response.write('<html><body>hello</body></html>');
        await request.response.close();
      });

      final LanScanner scanner = LanScanner(
        useBroadcast: false,
        verifyTimeout: const Duration(milliseconds: 600),
      );
      final bool verified =
          await scanner.verifySensing('127.0.0.1', server.port);

      expect(verified, isFalse);
      await server.close(force: true);
    });

    test('تمييز الإطار الصالح عن أي نص آخر', () {
      expect(LanScanner.isSensingPayload('{"type":"sensing_update"}'), isTrue);
      expect(LanScanner.isSensingPayload('{"features":{"variance":1}}'), isTrue);
      expect(LanScanner.isSensingPayload('{"nodes":[]}'), isTrue);
      expect(LanScanner.isSensingPayload('<html>404 not found</html>'), isFalse);
      expect(LanScanner.isSensingPayload('OK'), isFalse);
      expect(LanScanner.isSensingPayload(null), isFalse);
    });

    test('منفذ مفتوح لا يُوسم كبوابة، والتحقّق يرفع درجته', () {
      const LanCandidate open = LanCandidate(
        host: '192.168.8.142',
        port: 8000,
        latencyMs: 114,
      );
      const LanCandidate verified = LanCandidate(
        host: '192.168.8.142',
        port: 8000,
        latencyMs: 114,
        verified: true,
      );

      expect(open.isGatewayCandidate, isFalse);
      expect(open.sourceLabel, contains('ليست RuView'));
      expect(verified.isGatewayCandidate, isTrue);
      expect(verified.sourceLabel, contains('مُتحقَّق'));
      expect(verified.score, greaterThan(open.score));
      expect(open.copyWith(verified: true).verified, isTrue);
    });

    test('تقرير المسح يلخّص الأرقام الفعلية بصدق', () {
      const LanScanReport report = LanScanReport(
        networkLabel: '192.168.8.142 · بوابة 192.168.8.1',
        hostsScanned: 254,
        portsScanned: 5,
        probes: 1270,
        openPorts: 2,
        gateways: 0,
        durationMs: 3200,
        deep: true,
      );

      final String summary = report.arabicSummary;
      expect(summary, contains('254'));
      expect(summary, contains('1270'));
      expect(summary, contains('لا بوابة RuView'));
      expect(report.toJson()['gateways'], 0);
    });
  });
}
