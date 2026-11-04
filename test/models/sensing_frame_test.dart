import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/json_read.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/data/models/vital_signs.dart';

/// إطار كامل مطابق لما يبثّه خادم RuView الرسمي (ADR-019 + SensingUpdate).
Map<String, dynamic> officialFrameJson() => <String, dynamic>{
      'type': 'sensing_update',
      'timestamp': 1793562081.919,
      'source': 'esp32',
      'tick': 1024,
      'nodes': <Map<String, dynamic>>[
        <String, dynamic>{
          'node_id': 1,
          'rssi_dbm': -39.0,
          'position': <double>[2, 0, 1.5],
          'amplitude': <double>[12.1, 11.8, 12.4],
          'subcarrier_count': 3,
          'frame_rate_hz': 10.0,
          'stale': false,
        },
      ],
      'features': <String, dynamic>{
        'mean_rssi': -39.0,
        'variance': 2.34,
        'motion_band_power': 0.45,
        'breathing_band_power': 0.21,
        'dominant_freq_hz': 0.26,
        'change_points': 2,
        'spectral_power': 1.7,
      },
      'classification': <String, dynamic>{
        'motion_level': 'present_moving',
        'presence': true,
        'confidence': 0.87,
      },
      'signal_field': <String, dynamic>{
        'grid_size': <int>[20, 1, 20],
        'values': <double>[0.1, 0.9, 0.2],
      },
      'vital_signs': <String, dynamic>{
        'breathing_rate_bpm': 15.2,
        'heart_rate_bpm': 68.0,
        'breathing_confidence': 0.72,
        'heartbeat_confidence': 0.61,
        'signal_quality': 0.8,
      },
      'estimated_persons': 1,
      'signal_quality_score': 0.8,
      'quality_verdict': 'good',
      'persons': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'confidence': 0.9,
          'zone': 'zone_1',
          'position': <double>[2.4, 0, 3.1],
          'motion_score': 55.0,
          'bbox': <String, dynamic>{
            'x': 0.1,
            'y': 0.2,
            'width': 0.3,
            'height': 0.5,
          },
          'keypoints': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'nose',
              'x': 0.5,
              'y': 0.3,
              'z': 0.0,
              'confidence': 0.91,
            },
          ],
        },
      ],
    };

void main() {
  group('SensingFrame.fromJson', () {
    test('يقرأ جميع حقول الإطار الرسمي بشكل صحيح', () {
      final SensingFrame frame = SensingFrame.fromJson(officialFrameJson());

      expect(frame.type, 'sensing_update');
      expect(frame.source, 'esp32');
      expect(frame.tick, 1024);
      expect(frame.nodes, hasLength(1));
      expect(frame.nodes.first.nodeId, 1);
      expect(frame.nodes.first.rssiDbm, -39);
      expect(frame.features.motionBandPower, closeTo(0.45, 1e-9));
      expect(frame.classification.motionLevel, MotionLevel.moving);
      expect(frame.classification.presence, isTrue);
      expect(frame.persons, hasLength(1));
      expect(frame.persons.first.position, <double>[2.4, 0, 3.1]);
      expect(frame.estimatedPersons, 1);
      expect(frame.personCount, 1);
      expect(frame.hasPresence, isTrue);
      expect(frame.qualityVerdict, 'good');
      expect(frame.timestamp.millisecondsSinceEpoch, 1793562081919);
    });

    test('يحسب معدل التنفس والعلامات الحيوية', () {
      final SensingFrame frame = SensingFrame.fromJson(officialFrameJson());
      expect(frame.breathingRateBpm, 15.2);
      expect(frame.vitalSigns, isNotNull);
      expect(frame.vitalSigns!.hasHeartRate, isTrue);
      expect(frame.vitalSigns!.breathingStatus, BreathingStatus.normal);
      expect(frame.vitalSigns!.confidence, closeTo((0.72 + 0.61 + 0.8) / 3, 1e-9));
    });

    test('يدعم الأسماء البديلة للحقول (breathing_bpm / hr_proxy_bpm)', () {
      final SensingFrame frame = SensingFrame.fromJson(<String, dynamic>{
        'vital_signs': <String, dynamic>{
          'breathing_bpm': 22.4,
          'hr_proxy_bpm': 74.0,
          'heart_confidence': 0.4,
        },
      });

      expect(frame.vitalSigns!.breathingRateBpm, 22.4);
      expect(frame.vitalSigns!.heartRateBpm, 74.0);
      expect(frame.vitalSigns!.heartConfidence, 0.4);
      expect(frame.vitalSigns!.breathingStatus, BreathingStatus.fast);
    });

    test('يتعامل مع إطار ناقص الحقول دون استثناء', () {
      final SensingFrame frame = SensingFrame.fromJson(<String, dynamic>{});

      expect(frame.nodes, isEmpty);
      expect(frame.persons, isEmpty);
      expect(frame.classification.presence, isFalse);
      expect(frame.classification.motionLevel, MotionLevel.unknown);
      expect(frame.vitalSigns, isNull);
      expect(frame.hasPresence, isFalse);
      expect(frame.signalQuality, 0);
    });

    test('يميّز التوقيت بالمللي ثانية عن الثواني', () {
      final SensingFrame msFrame = SensingFrame.fromJson(<String, dynamic>{
        'timestamp': 1793562081919,
      });
      expect(msFrame.timestamp.millisecondsSinceEpoch, 1793562081919);

      final SensingFrame secFrame = SensingFrame.fromJson(<String, dynamic>{
        'timestamp': 1793562081.919,
      });
      expect(secFrame.timestamp.millisecondsSinceEpoch, 1793562081919);
    });

    test('يستنتج الحضور من عدد الأشخاص عند غياب علم التصنيف', () {
      final SensingFrame frame = SensingFrame.fromJson(<String, dynamic>{
        'persons': <Map<String, dynamic>>[
          <String, dynamic>{'id': 2, 'confidence': 0.7},
        ],
      });
      expect(frame.classification.presence, isFalse);
      expect(frame.hasPresence, isTrue);
      expect(frame.personCount, 1);
    });

    test('يحسب جودة الإشارة من RSSI عند غياب درجة الخادم', () {
      final SensingFrame frame = SensingFrame.fromJson(<String, dynamic>{
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{'node_id': 1, 'rssi_dbm': -35},
          <String, dynamic>{'node_id': 2, 'rssi_dbm': -90},
        ],
      });
      expect(frame.signalQuality, closeTo(0.5, 1e-9));
      expect(frame.averageRssi, closeTo(-62.5, 1e-9));
    });

    test('شدة الحركة تتبع مستوى التصنيف', () {
      final SensingFrame moving = SensingFrame.fromJson(officialFrameJson());
      final SensingFrame still = SensingFrame.fromJson(<String, dynamic>{
        'classification': <String, dynamic>{
          'motion_level': 'present_still',
          'presence': true,
          'confidence': 0.6,
        },
        'features': <String, dynamic>{'motion_band_power': 0.05},
      });

      expect(moving.motionIntensity, greaterThan(0.7));
      expect(still.motionIntensity, lessThan(0.3));
    });
  });

  group('VitalSigns', () {
    test('تصنيف حالات التنفس', () {
      expect(
        const VitalSigns(breathingRateBpm: 10).breathingStatus,
        BreathingStatus.slow,
      );
      expect(
        const VitalSigns(breathingRateBpm: 15).breathingStatus,
        BreathingStatus.normal,
      );
      expect(
        const VitalSigns(breathingRateBpm: 26).breathingStatus,
        BreathingStatus.fast,
      );
      expect(const VitalSigns().breathingStatus, BreathingStatus.unknown);
    });
  });

  group('JsonRead', () {
    test('يتعامل مع القيم النصية والأرقام المختلطة', () {
      expect(JsonRead.asDouble('12.5'), 12.5);
      expect(JsonRead.asDouble(null, 3), 3);
      expect(JsonRead.asInt('42'), 42);
      expect(JsonRead.asBool('true'), isTrue);
      expect(JsonRead.asBool(1), isTrue);
      expect(JsonRead.asString(null, 'x'), 'x');
      expect(JsonRead.asDoubleList(<Object?>[1, '2.5', null]), <double>[1, 2.5, 0]);
    });
  });
}
