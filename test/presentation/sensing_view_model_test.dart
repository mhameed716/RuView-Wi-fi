import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/connection_status.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/presentation/viewmodels/sensing_view_model.dart';

/// مصدر بيانات وهمي لاختبار الـ ViewModel بلا شبكة.
class FakeSensingSource implements SensingDataSource {
  final StreamController<SensingFrame> framesController =
      StreamController<SensingFrame>.broadcast();
  final StreamController<ConnectionSnapshot> connectionController =
      StreamController<ConnectionSnapshot>.broadcast();

  @override
  Stream<SensingFrame> get frames => framesController.stream;

  @override
  Stream<ConnectionSnapshot> get connection => connectionController.stream;

  Future<void> emitFrame(SensingFrame frame) async {
    framesController.add(frame);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emitConnection(ConnectionSnapshot snapshot) async {
    connectionController.add(snapshot);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await framesController.close();
    await connectionController.close();
  }
}

SensingFrame buildFrame({
  required String motionLevel,
  required bool presence,
  int persons = 0,
  double? breathing,
  double motionPower = 0.1,
  double quality = 0.8,
  DateTime? receivedAt,
}) {
  return SensingFrame.fromJson(
    <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': 1793562081.919,
      'source': 'esp32',
      'nodes': <Map<String, dynamic>>[
        <String, dynamic>{'node_id': 1, 'rssi_dbm': -44},
      ],
      'features': <String, dynamic>{'motion_band_power': motionPower},
      'classification': <String, dynamic>{
        'motion_level': motionLevel,
        'presence': presence,
        'confidence': 0.85,
      },
      'signal_quality_score': quality,
      'estimated_persons': persons,
      'vital_signs': <String, dynamic>{
        if (breathing != null) 'breathing_rate_bpm': breathing,
        'breathing_confidence': 0.7,
      },
      'persons': <Map<String, dynamic>>[
        for (int i = 0; i < persons; i++)
          <String, dynamic>{'id': i, 'confidence': 0.8},
      ],
    },
    receivedAt: receivedAt,
  );
}

void main() {
  late FakeSensingSource source;
  late SensingViewModel viewModel;

  setUp(() {
    source = FakeSensingSource();
    viewModel = SensingViewModel(repository: source);
  });

  tearDown(() async {
    viewModel.dispose();
    await source.close();
  });

  test('يسجّل حدث أول إطار عند بدء البث', () async {
    await source.emitFrame(
      buildFrame(motionLevel: 'absent', presence: false),
    );

    expect(viewModel.hasData, isTrue);
    expect(viewModel.events.first.title, 'بدأ استقبال بيانات الاستشعار');
    expect(viewModel.source, 'esp32');
  });

  test('يحدّث الحضور وعدد الأشخاص وشدة الحركة', () async {
    await source.emitFrame(buildFrame(motionLevel: 'absent', presence: false));
    await source.emitFrame(
      buildFrame(
        motionLevel: 'present_moving',
        presence: true,
        persons: 2,
        motionPower: 1.2,
      ),
    );

    expect(viewModel.hasPresence, isTrue);
    expect(viewModel.personCount, 2);
    expect(viewModel.motionLevel, MotionLevel.moving);
    expect(viewModel.motionIntensity, greaterThan(0.5));
    expect(
      viewModel.events.map((dynamic e) => e.title),
      contains('تم رصد حضور في المنطقة'),
    );
  });

  test('ينعّم معدل التنفس عبر الإطارات', () async {
    for (int i = 0; i < 6; i++) {
      await source.emitFrame(
        buildFrame(
          motionLevel: 'present_still',
          presence: true,
          persons: 1,
          breathing: 14 + i.toDouble(),
        ),
      );
    }

    final double? smoothed = viewModel.breathingRate;
    expect(smoothed, isNotNull);
    // التنعيم يجب أن يبقى داخل نطاق القراءات الخام (14..19).
    expect(smoothed!, greaterThan(13.5));
    expect(smoothed, lessThan(19.5));
    expect(viewModel.breathingHistory, isNotEmpty);
  });

  test('يسجّل أحداث الاتصال والأخطاء', () async {
    await source.emitConnection(
      const ConnectionSnapshot(status: ConnectionStatus.connected),
    );
    expect(viewModel.isConnected, isTrue);
    expect(
      viewModel.events.map((dynamic e) => e.title),
      contains('تم الاتصال بالبوابة'),
    );

    await source.emitConnection(
      const ConnectionSnapshot(
        status: ConnectionStatus.error,
        message: 'تعذّر الوصول إلى الخادم',
      ),
    );
    expect(viewModel.isConnected, isFalse);
    expect(
      viewModel.events.first.title,
      'تعذّر الاتصال بالبوابة',
    );
    expect(viewModel.events.first.detail, 'تعذّر الوصول إلى الخادم');
  });

  test('قطع الاتصال يصفّر السجل البياني', () async {
    await source.emitConnection(
      const ConnectionSnapshot(status: ConnectionStatus.connected),
    );
    await source.emitFrame(
      buildFrame(motionLevel: 'present_still', presence: true, persons: 1, breathing: 16),
    );
    expect(viewModel.breathingHistory, isNotEmpty);

    await source.emitConnection(
      const ConnectionSnapshot(status: ConnectionStatus.disconnected),
    );

    expect(viewModel.breathingHistory, isEmpty);
    expect(viewModel.motionHistory, isEmpty);
    expect(viewModel.breathingRate, isNull);
  });

  test('clearEvents يفرّغ السجل', () async {
    await source.emitFrame(buildFrame(motionLevel: 'absent', presence: false));
    expect(viewModel.events, isNotEmpty);
    viewModel.clearEvents();
    expect(viewModel.events, isEmpty);
  });

  test('لا يزيد السجل عن الحد الأقصى', () async {
    for (int i = 0; i < 90; i++) {
      await source.emitFrame(
        buildFrame(
          motionLevel: i.isEven ? 'present_moving' : 'present_still',
          presence: true,
          persons: 1,
        ),
      );
    }
    expect(viewModel.events.length, lessThanOrEqualTo(SensingViewModel.maxEvents));
  });
}
