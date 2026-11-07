import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/domain/twin/pbr_material.dart';
import 'package:ruview_wifi/domain/twin/room_model.dart';
import 'package:ruview_wifi/domain/twin/room_reconstructor.dart';

/// إطار اصطناعي: حقل إشارة 8×8 مع كتلة ثابتة قوية + شخص متحرك.
SensingFrame frameWithBlock({
  int tick = 0,
  bool includeBlock = true,
  double personX = 5.6,
  double personZ = 5.2,
}) {
  const int grid = 8;
  final List<double> values = <double>[];
  for (int z = 0; z < grid; z++) {
    for (int x = 0; x < grid; x++) {
      final bool inBlock = includeBlock && x >= 2 && x <= 6 && z >= 1 && z <= 2;
      values.add(inBlock ? 1.0 : 0.05);
    }
  }

  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': 1735000000 + tick,
      'source': 'test',
      'signal_field': <String, dynamic>{
        'grid_size': <int>[grid, 1, grid],
        'values': values,
      },
      'features': <String, dynamic>{
        'motion_band_power': 0.2,
        'variance': 1.2,
        'mean_rssi': -52.0,
      },
      'classification': <String, dynamic>{
        'presence': true,
        'motion_level': 'present_still',
        'confidence': 0.8,
      },
      'persons': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'confidence': 0.8,
          'zone': 'zone_1',
          'position': <double>[personX, 0, personZ],
        },
      ],
    },
    receivedAt: DateTime(2026, 1, 1).add(Duration(milliseconds: tick * 100)),
  );
}

void main() {
  group('RoomReconstructor', () {
    test('يبني شبكة إشغال ويكتشف عائقًا ثابتًا', () {
      final RoomReconstructor room = RoomReconstructor(rebuildEvery: 2);

      RoomModel model = RoomModel.empty;
      for (int tick = 0; tick < 12; tick++) {
        model = room.ingest(frameWithBlock(tick: tick));
      }

      expect(model.hasData, isTrue);
      expect(model.cells.length, model.cols * model.rows);
      expect(model.frames, 12);
      expect(model.obstacleCells, greaterThan(0));
      expect(model.freeAreaM2, greaterThan(0));
      expect(model.objects, isNotEmpty);
      expect(model.objects.first.material.id, isNotEmpty);
      expect(MaterialLibrary.all.map((PbrMaterial m) => m.id),
          contains(model.objects.first.material.id));
      expect(model.summary, contains('قطعة'));
    });

    test('بلا حقل إشارة لا تُخترع عوائق', () {
      final RoomReconstructor room = RoomReconstructor();
      final SensingFrame frame = SensingFrame.fromJson(
        <String, dynamic>{
          'type': 'sensing_update',
          'features': <String, dynamic>{'motion_band_power': 0.3},
          'classification': <String, dynamic>{
            'presence': true,
            'motion_level': 'present_moving',
          },
          'persons': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'confidence': 0.8,
              'position': <double>[1.5, 0, 1.5],
            },
          ],
        },
        receivedAt: DateTime(2026, 1, 1),
      );

      final RoomModel model = room.ingest(frame);
      expect(model.hasData, isTrue);
      expect(model.obstacleCells, 0);
      expect(model.objects, isEmpty);
    });

    test('reset يمسح المسح السابق', () {
      final RoomReconstructor room = RoomReconstructor();
      for (int tick = 0; tick < 6; tick++) {
        room.ingest(frameWithBlock(tick: tick));
      }
      expect(room.model.hasData, isTrue);

      room.reset();
      expect(room.model.hasData, isFalse);
      expect(room.frames, 0);
    });
  });

  group('RoomReconstructor.classifyCluster', () {
    test('الكتلة العريضة الطويلة → كنبة بخامة قماش', () {
      final ({FurnitureKind kind, PbrMaterial material}) result =
          RoomReconstructor.classifyCluster(
        widthM: 2.2,
        depthM: 0.9,
        touchesBorder: false,
      );

      expect(result.kind, FurnitureKind.sofa);
      expect(result.material.id, MaterialLibrary.fabric.id);
    });

    test('الكتلة الصغيرة المربّعة → طاولة خشبية', () {
      final ({FurnitureKind kind, PbrMaterial material}) result =
          RoomReconstructor.classifyCluster(
        widthM: 0.8,
        depthM: 0.8,
        touchesBorder: false,
      );

      expect(result.kind, FurnitureKind.table);
      expect(result.material.id, MaterialLibrary.oak.id);
    });

    test('الكتلة الطويلة الملاصقة للحدود → جدار حجري', () {
      final ({FurnitureKind kind, PbrMaterial material}) result =
          RoomReconstructor.classifyCluster(
        widthM: 4.0,
        depthM: 0.4,
        touchesBorder: true,
      );

      expect(result.kind, FurnitureKind.wall);
      expect(result.material.id, MaterialLibrary.stone.id);
    });

    test('الكتلة الرقيقة جدًا على الحدود → باب', () {
      final ({FurnitureKind kind, PbrMaterial material}) result =
          RoomReconstructor.classifyCluster(
        widthM: 2.4,
        depthM: 0.2,
        touchesBorder: true,
      );

      expect(result.kind, FurnitureKind.door);
    });

    test('الكتلة الضيقة الطويلة → خزانة خشب جوز', () {
      final ({FurnitureKind kind, PbrMaterial material}) result =
          RoomReconstructor.classifyCluster(
        widthM: 0.5,
        depthM: 0.9,
        touchesBorder: false,
      );

      expect(result.kind, FurnitureKind.cabinet);
      expect(result.material.id, MaterialLibrary.walnut.id);
    });
  });
}
