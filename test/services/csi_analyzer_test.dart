import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/services/csi_analyzer.dart';

/// بناء حزمة CSI ثنائية بصيغة ADR-018 لاختبار المحلّل.
Uint8List buildEsp32Frame({
  int nodeId = 1,
  int subcarriers = 8,
  int rssi = -42,
  int sequence = 1,
  int frequencyMhz = 2437,
  double scale = 10,
  double phase = 0,
}) {
  final int length = Esp32CsiFrame.headerBytes + subcarriers * 2;
  final ByteData data = ByteData(length);

  data.setUint32(0, Esp32CsiFrame.magic, Endian.little);
  data.setUint8(4, nodeId);
  data.setUint8(5, 1);
  data.setUint16(6, subcarriers, Endian.little);
  data.setUint32(8, frequencyMhz, Endian.little);
  data.setUint32(12, sequence, Endian.little);
  data.setInt8(16, rssi);
  data.setInt8(17, -90);
  data.setUint8(18, 0);
  data.setUint8(19, 0);

  for (int i = 0; i < subcarriers; i++) {
    final double value = scale * (1 + 0.35 * math.sin(i + phase));
    final int iValue = value.round().clamp(-128, 127);
    final int qValue = (value * 0.8).round().clamp(-128, 127);
    data.setInt8(Esp32CsiFrame.headerBytes + i * 2, iValue);
    data.setInt8(Esp32CsiFrame.headerBytes + i * 2 + 1, qValue);
  }

  return data.buffer.asUint8List();
}

void main() {
  group('Esp32CsiFrame.tryParse', () {
    test('يحلّل الترويسة والسعات', () {
      final Uint8List raw = buildEsp32Frame(subcarriers: 16, rssi: -55, nodeId: 3);
      final Esp32CsiFrame? frame = Esp32CsiFrame.tryParse(raw);

      expect(frame, isNotNull);
      expect(frame!.nodeId, 3);
      expect(frame.subcarrierCount, 16);
      expect(frame.rssi, -55);
      expect(frame.amplitudes, hasLength(16));
      expect(frame.amplitudes.first, greaterThan(0));
      expect(frame.meanAmplitude, greaterThan(0));
    });

    test('يرفض البيانات غير المطابقة أو المقتطعة', () {
      expect(Esp32CsiFrame.tryParse(Uint8List(4)), isNull);

      final Uint8List wrongMagic = buildEsp32Frame();
      wrongMagic[0] = 0x00;
      expect(Esp32CsiFrame.tryParse(wrongMagic), isNull);

      final Uint8List truncated = buildEsp32Frame(subcarriers: 16);
      expect(
        Esp32CsiFrame.tryParse(
          Uint8List.sublistView(truncated, 0, Esp32CsiFrame.headerBytes + 8),
        ),
        isNull,
      );
    });
  });

  group('CsiAnalyzer', () {
    test('ينتج رسالة sensing_update مطابقة للبنية الرسمية', () {
      final CsiAnalyzer analyzer = CsiAnalyzer();
      Map<String, dynamic>? update;

      for (int i = 0; i < 6; i++) {
        update = analyzer.ingest(
          buildEsp32Frame(scale: 10 + i.toDouble(), sequence: i),
          receivedAt: DateTime(2026, 1, 1, 12, 0, i),
        );
      }

      expect(update, isNotNull);
      expect(update!['type'], 'sensing_update');
      expect(update['nodes'], hasLength(1));
      expect(update['features'], isA<Map<String, dynamic>>());
      expect(update['classification'], isA<Map<String, dynamic>>());
      expect(update['signal_field'], isA<Map<String, dynamic>>());

      final Map<String, dynamic> node =
          (update['nodes'] as List<dynamic>).first as Map<String, dynamic>;
      expect(node['node_id'], 1);
      expect(node['rssi_dbm'], -42.0);
      expect(node['subcarrier_count'], 8);

      // يجب أن يكون قابلًا للتسلسل JSON (يُبثّ كما هو).
      expect(() => jsonEncode(update), returnsNormally);
    });

    test('يكتشف الحضور عند تباين السعة ويكتفي بالغياب عند ثباتها', () {
      final CsiAnalyzer stable = CsiAnalyzer();
      Map<String, dynamic>? stableUpdate;
      for (int i = 0; i < 12; i++) {
        stableUpdate = stable.ingest(
          buildEsp32Frame(scale: 10, sequence: i),
          receivedAt: DateTime(2026, 1, 1, 12, 0, i),
        );
      }

      final CsiAnalyzer varying = CsiAnalyzer();
      Map<String, dynamic>? varyingUpdate;
      for (int i = 0; i < 12; i++) {
        varyingUpdate = varying.ingest(
          buildEsp32Frame(scale: 8 + i.toDouble(), phase: i.toDouble()),
          receivedAt: DateTime(2026, 1, 1, 12, 0, i),
        );
      }

      final Map<String, dynamic> stableClassification =
          stableUpdate!['classification'] as Map<String, dynamic>;
      final Map<String, dynamic> varyingClassification =
          varyingUpdate!['classification'] as Map<String, dynamic>;

      expect(stableClassification['presence'], isFalse);
      expect(stableClassification['motion_level'], 'absent');
      expect(varyingClassification['presence'], isTrue);
      expect(varyingClassification['motion_level'], isNotNull);
    });

    test('يتجاهل الحزم غير الصالحة ويحصيها', () {
      final CsiAnalyzer analyzer = CsiAnalyzer();
      expect(analyzer.ingest(Uint8List.fromList(<int>[1, 2, 3])), isNull);
      expect(analyzer.ingest(Uint8List(64)), isNull);
      expect(analyzer.droppedCount, 2);
      expect(analyzer.packetCount, 0);
    });

    test('reset يصفّر الحالة بين الاتصالات', () {
      final CsiAnalyzer analyzer = CsiAnalyzer();
      analyzer.ingest(buildEsp32Frame());
      expect(analyzer.packetCount, 1);
      analyzer.reset();
      expect(analyzer.packetCount, 0);
      expect(analyzer.droppedCount, 0);
    });

    test('يدعم عدة عقد في نفس الوقت', () {
      final CsiAnalyzer analyzer = CsiAnalyzer();
      Map<String, dynamic>? update;
      for (int i = 0; i < 4; i++) {
        analyzer.ingest(buildEsp32Frame(nodeId: 1, sequence: i));
        update = analyzer.ingest(
          buildEsp32Frame(nodeId: 2, rssi: -60, sequence: i),
        );
      }

      final List<dynamic> nodes = update!['nodes'] as List<dynamic>;
      expect(nodes, hasLength(2));
      expect(
        nodes.map((dynamic node) => (node as Map<String, dynamic>)['node_id']),
        containsAll(<int>[1, 2]),
      );
    });
  });
}
