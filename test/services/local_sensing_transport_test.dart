import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/connection_settings.dart';
import 'package:ruview_wifi/data/models/connection_status.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/data/services/local_sensing_transport.dart';

/// مصدر المحاكاة الداخلي: يجب أن يُنتج إطارات صالحة تمرّ عبر كامل خط
/// المعالجة الحقيقي (نقل ← مستودع ← نماذج مجال) بلا شبكة ولا بوابة.
void main() {
  const ConnectionSettings simulatorSettings =
      ConnectionSettings(transport: TransportKind.simulator);

  group('إعدادات المحاكاة', () {
    test('المحاكاة لا تحتاج عنوانًا أو منفذًا صالحين', () {
      const ConnectionSettings settings = ConnectionSettings(
        host: '',
        port: 0,
        transport: TransportKind.simulator,
      );
      expect(settings.isValid, isTrue);
      expect(settings.transport.needsEndpoint, isFalse);
      expect(settings.transport.isSimulator, isTrue);
      expect(settings.webSocketUri, isNull);
      expect(settings.endpointLabel, contains('محاكاة'));
    });

    test('الاسم التخزيني والتحويل من الاسم يعملان', () {
      expect(TransportKind.simulator.storageName, 'simulator');
      expect(TransportKind.fromName('simulator'), TransportKind.simulator);
      expect(TransportKind.fromName('udp'), TransportKind.udp);
      expect(TransportKind.fromName(null), TransportKind.webSocket);
    });

    test('رحلة الحفظ والاستعادة تحافظ على المحاكاة', () {
      const ConnectionSettings original =
          ConnectionSettings(transport: TransportKind.simulator);
      final ConnectionSettings restored =
          ConnectionSettings.fromJson(original.toJson());
      expect(restored.transport, TransportKind.simulator);
      expect(restored.isValid, isTrue);
    });
  });

  group('LocalSensingTransport', () {
    test('يبثّ إطارات sensing_update بمفاصل كافية للرسم', () async {
      final LocalSensingTransport transport = LocalSensingTransport(
        frameInterval: const Duration(milliseconds: 40),
      );
      final List<TransportEvent> events = <TransportEvent>[];
      final StreamSubscription<TransportEvent> subscription =
          transport.events.listen(events.add);

      await transport.connect(simulatorSettings);
      expect(transport.isActive, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await subscription.cancel();
      await transport.dispose();

      final List<Object?> payloads = events
          .where((TransportEvent event) =>
              event.kind == TransportEventKind.frame)
          .map((TransportEvent event) => event.frame)
          .toList(growable: false);

      expect(payloads.length, greaterThanOrEqualTo(3));
      expect(
        events.any((TransportEvent event) =>
            event.kind == TransportEventKind.connected),
        isTrue,
      );

      final SensingFrame frame =
          SensingFrame.fromJson(payloads.first! as Map<String, dynamic>);
      expect(frame.type, 'sensing_update');
      expect(frame.source, contains('محاكاة'));
      expect(frame.persons, isNotEmpty);
      expect(frame.persons.first.keypoints.length, greaterThanOrEqualTo(5));
      expect(frame.classification.presence, isTrue);
      expect(frame.vitalSigns?.hasBreathing ?? false, isTrue);
      expect(frame.vitalSigns?.hasHeartRate ?? false, isTrue);
      expect(frame.nodes.length, 2);
      expect(frame.features.motionBandPower, greaterThan(0));
    });

    test('القطع يوقف البث ويعلن الانفصال', () async {
      final LocalSensingTransport transport = LocalSensingTransport(
        frameInterval: const Duration(milliseconds: 30),
      );
      final List<TransportEventKind> kinds = <TransportEventKind>[];
      final StreamSubscription<TransportEvent> subscription =
          transport.events.listen(
        (TransportEvent event) => kinds.add(event.kind),
      );

      await transport.connect(simulatorSettings);
      await transport.disconnect();
      expect(transport.isActive, isFalse);

      final int framesAfterDisconnect = kinds.length;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(kinds.length, framesAfterDisconnect);
      expect(kinds.contains(TransportEventKind.disconnected), isTrue);

      await subscription.cancel();
      await transport.dispose();
    });
  });

  group('SensingRepository مع المحاكاة', () {
    test('المستودع يحوّل إطارات المحاكاة ويعلن الاتصال', () async {
      final SensingRepository repository = SensingRepository();
      final List<SensingFrame> frames = <SensingFrame>[];
      final StreamSubscription<SensingFrame> subscription =
          repository.frames.listen(frames.add);

      await repository.connect(simulatorSettings);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(repository.snapshot.status, ConnectionStatus.connected);
      expect(frames, isNotEmpty);
      expect(repository.frameCount, greaterThanOrEqualTo(2));

      await subscription.cancel();
      await repository.dispose();
    });
  });
}
