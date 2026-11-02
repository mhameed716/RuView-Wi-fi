import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ruview_wifi/core/l10n/ar_strings.dart';
import 'package:ruview_wifi/data/models/connection_settings.dart';
import 'package:ruview_wifi/data/models/connection_status.dart';
import 'package:ruview_wifi/data/repositories/sensing_repository.dart';
import 'package:ruview_wifi/data/services/lan_scanner.dart';
import 'package:ruview_wifi/data/services/sensing_transport.dart';
import 'package:ruview_wifi/data/services/settings_repository.dart';
import 'package:ruview_wifi/presentation/viewmodels/connection_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ماسح وهمي: يعيد قائمة مرشّحين جاهزة ويسجّل الشبكة التي سُبق فيها.
class _FakeScanner extends LanScanner {
  _FakeScanner(this.results) : super(useBroadcast: false);

  List<LanCandidate> results;
  int scans = 0;
  NetworkContext? lastContext;

  @override
  Future<List<LanCandidate>> scan({
    required NetworkContext context,
    Set<String> savedHosts = const <String>{},
    bool deep = false,
  }) async {
    scans++;
    lastContext = context;
    return results;
  }
}

/// نقل وهمي بثلاثة أنماط: متصل ببيانات، متصل صامت، وفاشل.
class _FakeTransport implements SensingTransport {
  _FakeTransport(this.mode);

  final String mode;
  final StreamController<TransportEvent> _events =
      StreamController<TransportEvent>.broadcast();
  Timer? _timer;

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  bool get isActive => _timer != null;

  @override
  Future<void> connect(ConnectionSettings settings) async {
    if (mode == 'error') {
      _events.add(TransportEvent.failed('لا يوجد خادم على المنفذ'));
      return;
    }
    _events.add(TransportEvent.connected());
    if (mode == 'live') {
      _timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        _events.add(TransportEvent.data(_framePayload()));
      });
    }
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _events.add(TransportEvent.disconnected());
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _events.close();
  }
}

/// مراقب شبكة قابل للتحكم من الاختبار.
class _FakeWatcher extends NetworkWatcher {
  _FakeWatcher() : super(interval: const Duration(days: 1));

  void Function(NetworkContext context, bool changed)? callback;

  @override
  void start(void Function(NetworkContext context, bool changed) onUpdate) {
    callback = onUpdate;
  }

  void notify(NetworkContext context) => callback?.call(context, true);

  @override
  void dispose() {
    // لا مؤقّتات في النسخة الوهمية.
  }
}

Map<String, dynamic> _framePayload() => <String, dynamic>{
      'type': 'sensing_update',
      'features': <String, dynamic>{
        'motion_band_power': 0.42,
        'dominant_freq_hz': 1.25,
        'variance': 1.6,
      },
      'classification': <String, dynamic>{
        'motion_level': 'present_moving',
        'presence': true,
        'confidence': 0.86,
      },
    };

Future<void> _waitFor(
  bool Function() condition, {
  String reason = 'الشرط',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('انتهت المدة قبل تحقّق: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ConnectionViewModel build({
    required NetworkContext Function() context,
    required _FakeScanner scanner,
    required _FakeWatcher watcher,
    Map<String, String> modes = const <String, String>{},
  }) {
    final SensingRepository repository = SensingRepository(
      transportFactory: (ConnectionSettings settings) =>
          _FakeTransport(modes[settings.host] ?? 'live'),
    );
    final ConnectionViewModel model = ConnectionViewModel(
      repository: repository,
      settingsRepository: SettingsRepository(),
      scanner: scanner,
      networkWatcher: watcher,
      testEnvironmentDetector: () => false,
      networkDetector: () async => context(),
    );
    addTearDown(() async {
      model.dispose();
      await repository.dispose();
    });
    return model;
  }

  test('يتصل تلقائيًا بخادم RuView على شبكة راوتر 192.168.1.x', () async {
    final NetworkContext context =
        NetworkContext.fromAddresses(<String>['192.168.1.42']);
    final _FakeScanner scanner = _FakeScanner(<LanCandidate>[
      const LanCandidate(
        host: '192.168.1.1',
        port: 8765,
        latencyMs: 6,
        looksLikeRuView: true,
        isGateway: true,
      ),
    ]);
    final _FakeWatcher watcher = _FakeWatcher();
    final ConnectionViewModel model = build(
      context: () => context,
      scanner: scanner,
      watcher: watcher,
    );

    await model.initialize();
    await _waitFor(
      () => model.discoveryPhase == DiscoveryPhase.connected,
      reason: 'الاتصال التلقائي بالراوتر',
    );

    expect(scanner.scans, greaterThanOrEqualTo(1));
    expect(scanner.lastContext!.gatewayHost, '192.168.1.1');
    expect(model.host, '192.168.1.1');
    expect(model.isConnected, isTrue);
    await _waitFor(() => model.frameCount > 0, reason: 'وصول إطارات');
    expect(model.autoMessage, contains('192.168.1.1'));
    expect(model.lastEndpoint!.port, 8765);
  });

  test('ينتقل تلقائيًا عند التحوّل من الواي فاي إلى نقطة اتصال الهاتف',
      () async {
    final _FakeWatcher watcher = _FakeWatcher();
    final _FakeScanner scanner = _FakeScanner(<LanCandidate>[
      const LanCandidate(
        host: '192.168.1.1',
        port: 8765,
        looksLikeRuView: true,
        isGateway: true,
      ),
    ]);
    NetworkContext current =
        NetworkContext.fromAddresses(<String>['192.168.1.42']);
    final ConnectionViewModel model = build(
      context: () => current,
      scanner: scanner,
      watcher: watcher,
    );

    await model.initialize();
    await _waitFor(
      () => model.discoveryPhase == DiscoveryPhase.connected,
      reason: 'الاتصال الأول',
    );
    expect(model.host, '192.168.1.1');

    // المستخدم انتقل إلى نقطة اتصال هاتف أندرويد 192.168.43.x.
    current = NetworkContext.fromAddresses(<String>['192.168.43.129']);
    scanner.results = <LanCandidate>[
      const LanCandidate(
        host: '192.168.43.1',
        port: 3000,
        looksLikeRuView: true,
        isGateway: true,
      ),
    ];
    watcher.notify(current);
    await _waitFor(
      () =>
          model.discoveryPhase == DiscoveryPhase.connected &&
          model.host == '192.168.43.1',
      reason: 'إعادة الاتصال على شبكة الهاتف',
    );

    expect(model.network.prefix, '192.168.43');
    expect(scanner.scans, greaterThanOrEqualTo(2));
  });

  test('يتجاوز مرشّحًا يفتح الاتصال بلا بيانات ويجرّب التالي', () async {
    final _FakeScanner scanner = _FakeScanner(<LanCandidate>[
      const LanCandidate(
        host: '192.168.1.50',
        port: 8765,
        latencyMs: 2,
        looksLikeRuView: true,
      ),
      const LanCandidate(
        host: '192.168.1.1',
        port: 3000,
        latencyMs: 9,
        looksLikeRuView: true,
        isGateway: true,
      ),
    ]);
    final ConnectionViewModel model = build(
      context: () => NetworkContext.fromAddresses(<String>['192.168.1.42']),
      scanner: scanner,
      watcher: _FakeWatcher(),
      modes: <String, String>{'192.168.1.50': 'silent'},
    );

    await model.initialize();
    await _waitFor(
      () => model.discoveryPhase == DiscoveryPhase.connected,
      reason: 'تجاوز المرشّح الصامت',
    );

    expect(model.host, '192.168.1.1');
    expect(model.lastEndpoint!.port, 3000);
  });

  test('يُبلغ بصراحة عند عدم وجود خادم على الشبكة', () async {
    final _FakeScanner scanner = _FakeScanner(<LanCandidate>[]);
    final ConnectionViewModel model = build(
      context: () => NetworkContext.fromAddresses(<String>['10.0.0.7']),
      scanner: scanner,
      watcher: _FakeWatcher(),
    );

    await model.initialize();
    await _waitFor(
      () => model.discoveryPhase == DiscoveryPhase.notFound,
      reason: 'إعلان عدم العثور',
    );

    expect(model.autoMessage, ArStrings.autoNotFound);
    expect(model.candidates, isEmpty);
    expect(model.isConnected, isFalse);
  });

  test('بلا شبكة يذكر السبب بدل تعليق البحث', () async {
    final ConnectionViewModel model = build(
      context: () => NetworkContext.offline,
      scanner: _FakeScanner(<LanCandidate>[]),
      watcher: _FakeWatcher(),
    );

    await model.initialize();
    await _waitFor(
      () => model.discoveryPhase == DiscoveryPhase.notFound,
      reason: 'حالة بلا شبكة',
    );

    expect(model.autoMessage, ArStrings.autoNoNetwork);
  });

  test('يحترم إيقاف الاتصال التلقائي فلا يمسح الشبكة', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ruview.network.autoconnect.v1': false,
    });
    final _FakeScanner scanner = _FakeScanner(<LanCandidate>[
      const LanCandidate(host: '192.168.1.1', port: 8765),
    ]);
    final ConnectionViewModel model = build(
      context: () => NetworkContext.fromAddresses(<String>['192.168.1.42']),
      scanner: scanner,
      watcher: _FakeWatcher(),
    );

    await model.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(model.autoConnect, isFalse);
    expect(model.discoveryPhase, DiscoveryPhase.idle);
    expect(scanner.scans, 0);
  });
}
