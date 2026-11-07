import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/data/models/activity_event.dart';
import 'package:ruview_wifi/data/models/sensing_frame.dart';
import 'package:ruview_wifi/presentation/viewmodels/activity_rules.dart';

SensingFrame frame({
  required String motionLevel,
  required bool presence,
  double motionPower = 0.1,
  double? breathing,
  double? quality,
  int persons = 0,
}) {
  return SensingFrame.fromJson(<String, dynamic>{
    'type': 'sensing_update',
    'timestamp': 1793562081.919,
    'source': 'test',
    'nodes': <Map<String, dynamic>>[
      <String, dynamic>{'node_id': 1, 'rssi_dbm': -45},
    ],
    'features': <String, dynamic>{'motion_band_power': motionPower},
    'classification': <String, dynamic>{
      'motion_level': motionLevel,
      'presence': presence,
      'confidence': 0.8,
    },
    if (breathing != null)
      'vital_signs': <String, dynamic>{
        'breathing_rate_bpm': breathing,
        'breathing_confidence': 0.7,
      },
    if (quality != null) 'signal_quality_score': quality,
    'estimated_persons': persons,
    'persons': <Map<String, dynamic>>[
      for (int i = 0; i < persons; i++)
        <String, dynamic>{'id': i, 'confidence': 0.8},
    ],
  });
}

void main() {
  int counter = 0;
  counter = 0;

  ActivityContext context(
    SensingFrame? previous,
    SensingFrame current, {
    bool allowed = true,
    List<String>? requestedKeys,
  }) {
    return ActivityContext(
      previous: previous,
      current: current,
      nextId: () => ++counter,
      now: DateTime(2026, 1, 1, 12),
      cooldown: (String key) {
        requestedKeys?.add(key);
        return allowed;
      },
    );
  }

  group('ActivityRules', () {
    test('presenceRule: حدث عند رصد الحضور', () {
      final ActivityEvent? event = ActivityRules.presenceRule(
        context(
          frame(motionLevel: 'absent', presence: false),
          frame(motionLevel: 'present_still', presence: true, persons: 1),
        ),
      );

      expect(event, isNotNull);
      expect(event!.kind, ActivityKind.presence);
      expect(event.title, 'تم رصد حضور في المنطقة');
    });

    test('presenceRule: حدث عند مغادرة الشخص', () {
      final ActivityEvent? event = ActivityRules.presenceRule(
        context(
          frame(motionLevel: 'present_still', presence: true, persons: 1),
          frame(motionLevel: 'absent', presence: false),
        ),
      );

      expect(event!.title, 'غادر الشخص المنطقة');
    });

    test('presenceRule: لا حدث بدون تغيير أو بدون إطار سابق', () {
      expect(
        ActivityRules.presenceRule(
          context(
            frame(motionLevel: 'present_still', presence: true, persons: 1),
            frame(motionLevel: 'present_still', presence: true, persons: 1),
          ),
        ),
        isNull,
      );
      expect(
        ActivityRules.presenceRule(
          context(null, frame(motionLevel: 'absent', presence: false)),
        ),
        isNull,
      );
    });

    test('motionRule: يتبع الحرّاس الزمنية', () {
      final SensingFrame still =
          frame(motionLevel: 'present_still', presence: true, persons: 1);
      final SensingFrame moving =
          frame(motionLevel: 'present_moving', presence: true, persons: 1);

      final ActivityEvent? blocked =
          ActivityRules.motionRule(context(still, moving, allowed: false));
      expect(blocked, isNull);

      final List<String> keys = <String>[];
      final ActivityEvent? event =
          ActivityRules.motionRule(context(still, moving, requestedKeys: keys));
      expect(event, isNotNull);
      expect(event!.title, 'تم رصد حركة');
      expect(keys, contains('motion'));
    });

    test('breathingRule: يصدر حدثًا عند الخروج من النطاق الطبيعي', () {
      final ActivityEvent? fast = ActivityRules.breathingRule(
        context(
          frame(motionLevel: 'present_still', presence: true, breathing: 15),
          frame(motionLevel: 'present_still', presence: true, breathing: 26),
        ),
      );
      expect(fast!.title, 'تنفس سريع');

      final ActivityEvent? normal = ActivityRules.breathingRule(
        context(
          frame(motionLevel: 'present_still', presence: true, breathing: 26),
          frame(motionLevel: 'present_still', presence: true, breathing: 16),
        ),
      );
      expect(normal!.title, 'تنفس طبيعي');
    });

    test('breathingRule: لا حدث عند غياب القياس', () {
      expect(
        ActivityRules.breathingRule(
          context(
            frame(motionLevel: 'present_still', presence: true, breathing: 15),
            frame(motionLevel: 'present_still', presence: true),
          ),
        ),
        isNull,
      );
    });

    test('signalStrengthRule: ينبّه عند ضعف الإشارة ثم يعود', () {
      final ActivityEvent? weak = ActivityRules.signalStrengthRule(
        context(
          frame(motionLevel: 'present_still', presence: true, quality: 0.8),
          frame(motionLevel: 'present_still', presence: true, quality: 0.2),
        ),
      );
      expect(weak!.title, 'إشارة ضعيفة');

      final ActivityEvent? recovered = ActivityRules.signalStrengthRule(
        context(
          frame(motionLevel: 'present_still', presence: true, quality: 0.2),
          frame(motionLevel: 'present_still', presence: true, quality: 0.7),
        ),
      );
      expect(recovered!.title, 'استعادة قوة الإشارة');
    });

    test('peopleCountRule: يرصد تغيّر العدد داخل نفس الحضور', () {
      final ActivityEvent? event = ActivityRules.peopleCountRule(
        context(
          frame(motionLevel: 'present_still', presence: true, persons: 1),
          frame(motionLevel: 'present_still', presence: true, persons: 2),
        ),
      );
      expect(event!.title, 'تغيّر عدد الأشخاص');
      expect(event.detail, contains('2'));
    });

    test('RuleCooldowns: يمنع التكرار المتلاحق', () {
      final RuleCooldowns cooldowns = RuleCooldowns(
        overrides: <String, Duration>{'motion': const Duration(seconds: 10)},
      );
      final DateTime now = DateTime(2026, 1, 1, 12);

      expect(cooldowns.pass('motion', now), isTrue);
      expect(cooldowns.pass('motion', now.add(const Duration(seconds: 3))), isFalse);
      expect(cooldowns.pass('motion', now.add(const Duration(seconds: 20))), isTrue);
    });
  });
}
