import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/connection_settings.dart';

void main() {
  group('ConnectionSettings', () {
    test('الإعدادات الافتراضية صالحة وتشير إلى مسار /ws/sensing', () {
      const ConnectionSettings settings = ConnectionSettings();
      expect(settings.isValid, isTrue);
      expect(settings.webSocketUri.toString(), 'ws://192.168.1.100:8765/ws/sensing');
    });

    test('يرفض العناوين والمنافذ غير الصالحة', () {
      expect(const ConnectionSettings(host: '').isValidHost, isFalse);
      expect(const ConnectionSettings(host: 'http://10.0.0.1').isValidHost, isFalse);
      expect(const ConnectionSettings(host: 'a b').isValidHost, isFalse);
      expect(const ConnectionSettings(port: 0).isValidPort, isFalse);
      expect(const ConnectionSettings(port: 70000).isValidPort, isFalse);
      expect(const ConnectionSettings(host: 'ruview.local').isValidHost, isTrue);
      expect(const ConnectionSettings(host: '192.168.1.7').isValidHost, isTrue);
    });

    test('يبني رابط wss عند تفعيل التشفير', () {
      const ConnectionSettings settings = ConnectionSettings(
        host: '10.0.0.5',
        port: 443,
        secure: true,
      );
      expect(settings.webSocketUri.toString(), 'wss://10.0.0.5:443/ws/sensing');
    });

    test('يضيف ترويسة Bearer فقط عند وجود رمز', () {
      const ConnectionSettings withoutToken = ConnectionSettings();
      expect(withoutToken.authHeaders, isEmpty);

      const ConnectionSettings withToken =
          ConnectionSettings(authToken: ' secret-token ');
      expect(withToken.authHeaders['Authorization'], 'Bearer secret-token');
      expect(withToken.hasToken, isTrue);
    });

    test('رابط UDP لا يستخدم مسار WebSocket', () {
      const ConnectionSettings settings = ConnectionSettings(
        transport: TransportKind.udp,
        port: 5005,
      );
      expect(settings.wsPath, isEmpty);
      expect(settings.endpointLabel, '192.168.1.100:5005');
    });

    test('رحلة ذهاب وعودة عبر JSON', () {
      const ConnectionSettings original = ConnectionSettings(
        host: '192.168.50.20',
        port: 3001,
        transport: TransportKind.udp,
        authToken: 'abc',
        secure: true,
      );

      final ConnectionSettings restored =
          ConnectionSettings.fromJson(original.toJson());

      expect(restored.host, original.host);
      expect(restored.port, original.port);
      expect(restored.transport, TransportKind.udp);
      expect(restored.authToken, 'abc');
      expect(restored.secure, isTrue);
    });

    test('copyWith يحافظ على القيم غير المعدّلة', () {
      const ConnectionSettings base = ConnectionSettings(host: '192.168.1.9');
      final ConnectionSettings updated = base.copyWith(port: 3000);
      expect(updated.host, '192.168.1.9');
      expect(updated.port, 3000);
    });
  });
}
