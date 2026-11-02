import 'dart:async';
import 'dart:io';

import '../models/connection_settings.dart';

/// سياق الشبكة المحلية الحالية (بلا أذونات إضافية: عناوين IP فقط).
class NetworkContext {
  const NetworkContext({
    required this.localAddresses,
    required this.prefix,
    required this.gatewayHost,
    required this.fingerprint,
  });

  /// لا شبكة.
  static const NetworkContext offline = NetworkContext(
    localAddresses: <String>[],
    prefix: '',
    gatewayHost: null,
    fingerprint: 'offline',
  );

  /// عناوين الجهاز IPv4 على الشبكة المحلية.
  final List<String> localAddresses;

  /// بادئة الشبكة من نوع /24 (مثال: `192.168.1`).
  final String prefix;

  /// IP البوابة (الراوتر) المُستنتج.
  final String? gatewayHost;

  /// بصمة مستقرة للشبكة الحالية — تتغيّر عند الانتقال لشبكة أخرى.
  final String fingerprint;

  bool get isConnected => localAddresses.isNotEmpty;

  String get label {
    if (!isConnected) return 'بلا شبكة';
    if (gatewayHost == null) return localAddresses.first;
    return '$prefix.0/24 · بوابة $gatewayHost';
  }

  /// يقرأ واجهات الشبكة فعليًا (يفشل بأمان إلى [offline]).
  static Future<NetworkContext> detect() async {
    try {
      final List<NetworkInterface> interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      final List<String> addresses = <String>[];
      for (final NetworkInterface interface in interfaces) {
        for (final InternetAddress address in interface.addresses) {
          if (address.isLoopback) continue;
          final String raw = address.address;
          if (raw.startsWith('169.254.')) continue;
          if (!_isPrivate(raw)) continue;
          addresses.add(raw);
        }
      }
      return fromAddresses(addresses);
    } catch (_) {
      return offline;
    }
  }

  /// بناء سياق من قائمة عناوين (دالة نقية قابلة للاختبار).
  static NetworkContext fromAddresses(List<String> addresses) {
    final List<String> clean = <String>[];
    for (final String address in addresses) {
      final String trimmed = address.trim();
      if (trimmed.isEmpty || clean.contains(trimmed)) continue;
      if (!_isPrivate(trimmed)) continue;
      clean.add(trimmed);
    }
    if (clean.isEmpty) return offline;

    final String primary = clean.first;
    final String prefix = prefixOf(primary);
    return NetworkContext(
      localAddresses: clean,
      prefix: prefix,
      gatewayHost: '$prefix.1',
      fingerprint: clean.map((String ip) => prefixOf(ip)).toSet().join('|'),
    );
  }

  /// `192.168.1.42` → `192.168.1`.
  static String prefixOf(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length < 3) return ip;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  static bool _isPrivate(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length != 4) return false;
    final int? a = int.tryParse(parts[0]);
    final int? b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}

/// مرشّح اتصال اكتُشف على الشبكة.
class LanCandidate {
  const LanCandidate({
    required this.host,
    required this.port,
    this.transport = TransportKind.webSocket,
    this.latencyMs = 0,
    this.looksLikeRuView = false,
    this.isGateway = false,
    this.isSaved = false,
    this.source = 'مسح',
  });

  factory LanCandidate.fromJson(Object? json) {
    if (json is! Map) {
      return const LanCandidate(host: '0.0.0.0', port: 0);
    }
    int readInt(String key, int fallback) {
      final Object? value = json[key];
      if (value is num) return value.toInt();
      return fallback;
    }

    return LanCandidate(
      host: json['host'] is String ? json['host'] as String : '0.0.0.0',
      port: readInt('port', 8765),
      transport: TransportKind.fromName(json['transport'] as String?),
      latencyMs: readInt('latency_ms', 0),
      looksLikeRuView: json['ruview'] == true,
      isGateway: json['gateway'] == true,
      isSaved: json['saved'] == true,
      source: json['source'] is String ? json['source'] as String : 'مسح',
    );
  }

  final String host;
  final int port;
  final TransportKind transport;

  /// زمن الاستجابة بالمللي ثانية (أقل = أفضل).
  final int latencyMs;

  /// هل استجاب كخادم RuView فعلًا (HTTP/WebSocket)؟
  final bool looksLikeRuView;

  final bool isGateway;
  final bool isSaved;

  /// مصدر الاكتشاف: «محفوظ» / «بوابة» / «مسح».
  final String source;

  /// درجة الثقة بالمرشّح — الأعلى يُجرَّب أولًا.
  int get score {
    int value = 0;
    if (looksLikeRuView) value += 100;
    if (isSaved) value += 45;
    if (isGateway) value += 18;
    if (transport == TransportKind.webSocket) value += 10;
    if (port == 8765) value += 6;
    value -= (latencyMs / 25).round().clamp(0, 20);
    return value;
  }

  String get label => '$host:$port';

  String get sourceLabel {
    if (looksLikeRuView) return 'خادم RuView';
    if (isSaved) return 'آخر اتصال ناجح';
    if (isGateway) return 'بوابة الشبكة';
    return source;
  }

  ConnectionSettings toSettings({
    String authToken = '',
    bool secure = false,
  }) =>
      ConnectionSettings(
        host: host,
        port: port,
        transport: transport,
        authToken: authToken,
        secure: secure,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'port': port,
        'transport': transport.storageName,
        'latency_ms': latencyMs,
        'ruview': looksLikeRuView,
        'gateway': isGateway,
        'saved': isSaved,
        'source': source,
      };

  @override
  String toString() => 'LanCandidate($label, score=$score)';
}

/// ماسح الشبكة المحلية: يجعل التطبيق يعمل على **أي راوتر/شبكة** بلا إعداد يدوي.
///
/// الاستراتيجية (سريعة ثم شاملة):
///  1. مرشّحات فورية: آخر اتصال ناجح، بوابة الراوتر، عنوان الجهاز نفسه.
///  2. مسح عميق عند الحاجة: كل عناوين /24 على منافذ RuView الشائعة
///     (8765، 3000، 3001، 8080) بتوازٍ محدود.
///  3. فحص HTTP خفيف يميّز خادم RuView عن أي منفذ مفتوح آخر.
class LanScanner {
  LanScanner({
    this.ports = const <int>[8765, 3000, 3001, 8080],
    this.connectTimeout = const Duration(milliseconds: 260),
    this.concurrency = 48,
    this.maxScanDuration = const Duration(seconds: 7),
  });

  final List<int> ports;
  final Duration connectTimeout;
  final int concurrency;
  final Duration maxScanDuration;

  /// يبني قائمة عناوين المرشّحين (دالة نقية تُختبر مباشرة).
  static List<String> hostsFor(
    NetworkContext context, {
    bool deep = false,
    Set<String> extra = const <String>{},
  }) {
    if (!context.isConnected) return extra.toList(growable: false);

    final List<String> hosts = <String>[];
    void add(String? host) {
      if (host == null || host.isEmpty) return;
      if (!hosts.contains(host)) hosts.add(host);
    }

    for (final String saved in extra) {
      add(saved);
    }
    add(context.gatewayHost);
    for (final String local in context.localAddresses) {
      add(local);
    }
    add('${context.prefix}.1');
    add('${context.prefix}.254');
    add('${context.prefix}.2');
    add('${context.prefix}.100');

    if (deep) {
      for (int i = 1; i <= 254; i++) {
        add('${context.prefix}.$i');
      }
    }
    return List<String>.unmodifiable(hosts);
  }

  /// ترتيب المرشّحين: الأعلى ثقة أولًا، ثم الأسرع.
  static List<LanCandidate> ranked(Iterable<LanCandidate> candidates) {
    final List<LanCandidate> list = candidates.toList(growable: false);
    list.sort((LanCandidate a, LanCandidate b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.latencyMs.compareTo(b.latencyMs);
    });
    return list;
  }

  /// فحص منفذ واحد على عنوان واحد.
  Future<LanCandidate?> probe(
    String host,
    int port, {
    bool isGateway = false,
    bool isSaved = false,
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
      final int latency = watch.elapsedMilliseconds;

      bool looksLikeRuView = false;
      try {
        socket.write(
          'GET /health HTTP/1.1\r\n'
          'Host: $host:$port\r\n'
          'User-Agent: RuView-WiFi/1.3\r\n'
          'Connection: close\r\n\r\n',
        );
        await socket.flush();
        final List<int> buffer = <int>[];
        await for (final List<int> chunk in socket
            .timeout(const Duration(milliseconds: 450))
            .take(1)) {
          buffer.addAll(chunk);
        }
        final String text =
            String.fromCharCodes(buffer.take(2048)).toLowerCase();
        looksLikeRuView = text.contains('ruview') ||
            text.contains('sensing') ||
            text.contains('subcarrier') ||
            text.contains('101 switching') ||
            text.startsWith('http/1.1 200') ||
            text.startsWith('http/1.0 200');
      } catch (_) {
        // منفذ مفتوح لكنه لا يتحدّث HTTP — يبقى مرشّحًا ضعيفًا.
      }

      return LanCandidate(
        host: host,
        port: port,
        latencyMs: latency,
        looksLikeRuView: looksLikeRuView,
        isGateway: isGateway,
        isSaved: isSaved,
        source: isSaved ? 'محفوظ' : (isGateway ? 'بوابة' : 'مسح'),
      );
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
      watch.stop();
    }
  }

  /// مسح كامل. يعيد المرشّحين مرتبين بالأفضلية.
  Future<List<LanCandidate>> scan({
    required NetworkContext context,
    Set<String> savedHosts = const <String>{},
    bool deep = false,
  }) async {
    if (!context.isConnected) return const <LanCandidate>[];

    final Stopwatch watch = Stopwatch()..start();
    final List<String> hosts = hostsFor(
      context,
      deep: deep,
      extra: savedHosts,
    );
    final List<LanCandidate> found = <LanCandidate>[];

    for (int index = 0; index < hosts.length; index += concurrency) {
      if (watch.elapsed > maxScanDuration) break;
      final List<String> batch = hosts.sublist(
        index,
        (index + concurrency).clamp(0, hosts.length),
      );

      final List<Future<void>> tasks = <Future<void>>[];
      for (final String host in batch) {
        for (final int port in ports) {
          tasks.add(
            probe(
              host,
              port,
              isGateway: host == context.gatewayHost,
              isSaved: savedHosts.contains(host),
            ).then((LanCandidate? candidate) {
              if (candidate != null) found.add(candidate);
            }),
          );
        }
      }
      await Future.wait<void>(tasks);
    }

    return ranked(found);
  }
}

/// مراقب تغيّر الشبكة: يكتشف الانتقال بين شبكتين بلا أي إذن إضافي.
class NetworkWatcher {
  NetworkWatcher({
    this.interval = const Duration(seconds: 5),
    Future<NetworkContext> Function()? detector,
  }) : _detector = detector ?? NetworkContext.detect;

  final Duration interval;
  final Future<NetworkContext> Function() _detector;

  Timer? _timer;
  String _fingerprint = NetworkContext.offline.fingerprint;
  bool _busy = false;
  bool _disposed = false;

  NetworkContext last = NetworkContext.offline;

  /// يبدأ المراقبة: كل [interval] يفحص العناوين، ويُنبّه عند تغيّر البصمة.
  void start(void Function(NetworkContext context, bool changed) onUpdate) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick(onUpdate));
    unawaited(_tick(onUpdate));
  }

  Future<void> _tick(
    void Function(NetworkContext context, bool changed) onUpdate,
  ) async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final NetworkContext context = await _detector();
      last = context;
      final bool changed = context.fingerprint != _fingerprint;
      _fingerprint = context.fingerprint;
      if (!_disposed) onUpdate(context, changed);
    } finally {
      _busy = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
