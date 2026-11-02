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

    test('المسح العميق يغطّي كل عناوين /24', () {
      final NetworkContext context =
          NetworkContext.fromAddresses(<String>['192.168.0.10']);
      final List<String> hosts = LanScanner.hostsFor(context, deep: true);

      expect(hosts.length, greaterThanOrEqualTo(254));
      expect(hosts, contains('192.168.0.1'));
      expect(hosts, contains('192.168.0.254'));
    });

    test('بلا شبكة لا عناوين للمسح', () {
      expect(
        LanScanner.hostsFor(NetworkContext.offline, deep: true),
        isEmpty,
      );
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
  });
}
