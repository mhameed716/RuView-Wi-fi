import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/connection_settings.dart';

/// سياق الشبكة المحلية الحالية (بلا أذونات إضافية: عناوين IP فقط).
///
/// يدعم **عدة واجهات في الوقت نفسه** — وهو الحال الشائع على الهاتف:
/// واي فاي منزلي + نقطة اتصال شخصية، أو شبكة 10.x في المكتب و192.168.x في البيت.
class NetworkContext {
  const NetworkContext({
    required this.localAddresses,
    required this.prefixes,
    required this.fingerprint,
  });

  /// لا شبكة.
  static const NetworkContext offline = NetworkContext(
    localAddresses: <String>[],
    prefixes: <String>[],
    fingerprint: 'offline',
  );

  /// عناوين الجهاز IPv4 على الشبكات المحلية.
  final List<String> localAddresses;

  /// بادئات الشبكات من نوع /24 (مثال: `192.168.1`، `192.168.43`).
  final List<String> prefixes;

  /// بصمة مستقرة للشبكة الحالية — تتغيّر عند الانتقال لشبكة أخرى.
  final String fingerprint;

  bool get isConnected => localAddresses.isNotEmpty && prefixes.isNotEmpty;

  /// البادئة الأساسية (الأولى).
  String get prefix => prefixes.isEmpty ? '' : prefixes.first;

  /// بوابة الشبكة الأساسية (الراوتر غالبًا).
  String? get gatewayHost => prefixes.isEmpty ? null : '${prefixes.first}.1';

  /// بوابات كل الشبكات المتصلة (واي فاي + نقطة اتصال…).
  List<String> get gatewayHosts =>
      prefixes.map((String prefix) => '$prefix.1').toList(growable: false);

  String get label {
    if (!isConnected) return 'بلا شبكة';
    if (prefixes.length == 1) {
      return '${localAddresses.first} · بوابة ${gatewayHosts.first}';
    }
    return '${localAddresses.first} +${prefixes.length - 1} شبكات '
        '· بوابات ${gatewayHosts.join('، ')}';
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
    final List<String> prefixes = <String>[];
    for (final String address in addresses) {
      final String trimmed = address.trim();
      if (trimmed.isEmpty || clean.contains(trimmed)) continue;
      if (!_isPrivate(trimmed)) continue;
      clean.add(trimmed);
      final String prefix = prefixOf(trimmed);
      if (!prefixes.contains(prefix)) prefixes.add(prefix);
    }
    if (clean.isEmpty) return offline;

    return NetworkContext(
      localAddresses: List<String>.unmodifiable(clean),
      prefixes: List<String>.unmodifiable(prefixes),
      fingerprint: (prefixes.toSet().toList()..sort()).join('|'),
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
    // نطاق CGNAT (100.64/10) — تستخدمه بعض الشبكات المُدارة وأنفاق Tailscale.
    if (a == 100 && b >= 64 && b <= 127) return true;
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
    this.verified = false,
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
      transport: TransportKind.fromName(
        json['transport'] is String ? json['transport'] as String : null,
      ),
      latencyMs: readInt('latency_ms', 0),
      looksLikeRuView: json['ruview'] == true,
      verified: json['verified'] == true,
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

  /// هل استجاب كخادم RuView فعلًا (بصمة HTTP)؟
  final bool looksLikeRuView;

  /// إثبات قاطع: مصافحة WebSocket ناجحة على مسار الاستشعار + وصول إطار
  /// `sensing_update` صالح من هذا المنفذ. هذا هو الفحص «الحقيقي» الذي لا
  /// يعتمد على مجرّد فتح المنفذ.
  final bool verified;

  final bool isGateway;
  final bool isSaved;

  /// مصدر الاكتشاف: «محفوظ» / «بوابة» / «بثّ» / «مسح».
  final String source;

  /// درجة الثقة بالمرشّح — الأعلى يُجرَّب أولًا.
  int get score {
    int value = 0;
    if (verified) value += 200;
    if (looksLikeRuView) value += 100;
    if (isSaved) value += 45;
    if (isGateway) value += 18;
    if (transport == TransportKind.webSocket) value += 10;
    if (port == 8765) value += 6;
    final int penalty = math.min(20, math.max(0, (latencyMs / 25).round()));
    return value - penalty;
  }

  String get label => '$host:$port';

  String get sourceLabel {
    if (verified) return 'بوابة RuView مُتحقَّق منها';
    if (looksLikeRuView) return 'خادم RuView';
    if (isSaved) return 'محفوظ سابقًا';
    if (isGateway) return 'بوابة الشبكة';
    return 'منفذ مفتوح — ليست RuView';
  }

  /// هل يستحق أن يُجرَّب تلقائيًا كبوابة استشعار؟
  bool get isGatewayCandidate => verified || looksLikeRuView;

  LanCandidate copyWith({bool? verified}) => LanCandidate(
        host: host,
        port: port,
        transport: transport,
        latencyMs: latencyMs,
        looksLikeRuView: looksLikeRuView,
        verified: verified ?? this.verified,
        isGateway: isGateway,
        isSaved: isSaved,
        source: source,
      );

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
        'verified': verified,
        'gateway': isGateway,
        'saved': isSaved,
        'source': source,
      };

  @override
  String toString() => 'LanCandidate($label, score=$score)';
}

/// تقرير مسح فعلي قابل للعرض والمشاركة — أرقام حقيقية لا تقديرات.
///
/// الغرض: يرى المستخدم بالضبط ماذا فُحص، فلا يبقى «مسح» مجهولًا ولا تظهر
/// بوابة وهمية.
class LanScanReport {
  const LanScanReport({
    required this.networkLabel,
    required this.hostsScanned,
    required this.portsScanned,
    required this.probes,
    required this.openPorts,
    required this.gateways,
    required this.durationMs,
    required this.deep,
  });

  final String networkLabel;
  final int hostsScanned;
  final int portsScanned;

  /// عدد محاولات الاتصال الفعلية (مضيف × منفذ).
  final int probes;

  /// منافذ استجابت (TCP) لكنها ليست بوابة RuView.
  final int openPorts;

  /// بوابات RuView (بصمة أو تحقّق WebSocket كامل).
  final int gateways;

  final int durationMs;
  final bool deep;

  String get arabicSummary {
    final String scope =
        deep ? 'مسح عميق لكل الشبكة' : 'مسح سريع (عناوين مهمة فقط)';
    final String gatewaysText = gateways == 0
        ? 'لا بوابة RuView'
        : '$gateways بوابة RuView';
    return '$scope · ${hostsScanned} عنوانًا × $portsScanned منافذ = $probes '
            'محاولة · $openPorts منفذ مفتوح · $gatewaysText · '
            '${(durationMs / 1000).toStringAsFixed(1)} ث';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'network': networkLabel,
        'hosts': hostsScanned,
        'ports': portsScanned,
        'probes': probes,
        'open_ports': openPorts,
        'gateways': gateways,
        'duration_ms': durationMs,
        'deep': deep,
      };
}

/// ماسح الشبكة المحلية: يجعل التطبيق يعمل على **أي راوتر أو نقطة اتصال**.
///
/// الاستراتيجية:
///  1. مرشّحات فورية: آخر اتصال ناجح، بوابات كل الشبكات، عنوان الجهاز.
///  2. مسح عميق: كل عناوين /24 لكل واجهة (واي فاي + نقطة اتصال معًا)
///     على منافذ RuView الشائعة، كل المنافذ بالتوازي وبميزانية زمنية.
///  3. **بثّ UDP** على منفذ الاكتشاف (5005) لالتقاط البوابات التي تُعلن عن
///     نفسها (يعمل حتى حين يحجب الراوتر مسح TCP بسبب عزل العملاء).
///  4. فحص HTTP خفيف يتحقق من بصمة RuView، وتوقّف مبكر عند أول تطابق
///     لتسريع الاتصال على الشبكات الكبيرة.
class LanScanner {
  LanScanner({
    this.ports = const <int>[8765, 3000, 3001, 8000, 8080],
    this.connectTimeout = const Duration(milliseconds: 220),
    this.concurrency = 96,
    this.maxScanDuration = const Duration(seconds: 9),
    this.discoveryPort = 5005,
    this.useBroadcast = true,
    this.maxVerifications = 6,
    this.verifyTimeout = const Duration(milliseconds: 1500),
  });

  /// منافذ RuView الشائعة: 8765 (WS للاستشعار)، 3000/3001 (REST/WS الرسمي)،
  /// 8000 (مسار الوضعية `/api/v1/stream/pose`)، ثم 8080 (أدوات/معاينات).
  final List<int> ports;
  final Duration connectTimeout;
  final int concurrency;
  final Duration maxScanDuration;

  /// منفذ بثّ الاكتشاف (نفس منفذ عُقد ESP32 في RuView — لا يتعارض مع الاستقبال).
  final int discoveryPort;

  /// تفعيل بثّ UDP للاكتشاف.
  final bool useBroadcast;

  /// أقصى عدد مرشّحين يُتحقَّق منهم بمصافحة WebSocket فعلية في المسح الواحد.
  final int maxVerifications;

  /// مهلة التحقق لكل مرشّح (مصافحة + أول إطار).
  final Duration verifyTimeout;

  /// آخر تقرير مسح فعلي (لل عرض والمشاركة).
  LanScanReport? lastReport;

  /// أسماء مضيفين قد تُعرّف البوابة نفسها بها (تُجرَّب بأولوية منخفضة).
  static const List<String> hostnames = <String>[
    'ruview.local',
    'ruview',
    'ruview-gateway.local',
  ];

  /// سلسلة تعريف البثّ.
  static const String discoveryMagic = 'RUVIEW_DISCOVERY_V1';

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
    // بوابات كل الشبكات أولًا (الخادم غالبًا على الراوتر أو نقطة الاتصال).
    for (final String gateway in context.gatewayHosts) {
      add(gateway);
    }
    for (final String local in context.localAddresses) {
      add(local);
    }
    for (final String prefix in context.prefixes) {
      add('$prefix.254');
      add('$prefix.2');
      add('$prefix.100');
    }
    // خادم RuView يعمل على الهاتف نفسه (نقطة اتصال + خادم على الجهاز ذاته).
    add('127.0.0.1');
    for (final String hostname in hostnames) {
      add(hostname);
    }

    if (deep) {
      for (final String prefix in context.prefixes) {
        for (int i = 1; i <= 254; i++) {
          add('$prefix.$i');
        }
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
        looksLikeRuView = _looksLikeRuViewBody(text);
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

  /// إثبات قاطع: هل هذا العنوان منفذ استشعار RuView فعلًا؟
  ///
  /// نفتح WebSocket حقيقيًا على `/ws/sensing` (ثم مسار الوضعية كبديل)،
  /// وننتظر أول رسالة؛ نقبلها فقط إن كانت إطار `sensing_update` صالحًا
  /// (يحمل `classification` أو `features` أو `nodes` أو نوع الإطار).
  /// منفذ مفتوح لا يجتاز هذا الفحص = ليس بوابة RuView.
  Future<bool> verifySensing(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    final Duration budget = timeout ?? verifyTimeout;
    for (final String path in const <String>[
      '/ws/sensing',
      '/api/v1/stream/pose',
    ]) {
      WebSocket? socket;
      try {
        socket = await WebSocket.connect('ws://$host:$port$path')
            .timeout(budget);
        final Object? message = await socket.first.timeout(budget);
        if (isSensingPayload(message)) return true;
      } catch (_) {
        // فشل المصافحة أو لا إطار: نجرّب المسار البديل.
      } finally {
        final WebSocket? open = socket;
        if (open != null) {
          try {
            await open.close();
          } catch (_) {
            // تجاهل أخطاء الإغلاق.
          }
        }
      }
    }
    return false;
  }

  /// هل الرسالة إطار استشعار RuView صالح؟ (دالة نقية تُختبر مباشرة)
  static bool isSensingPayload(Object? message) {
    final String text;
    if (message is String) {
      text = message;
    } else if (message is List<int>) {
      text = utf8.decode(message, allowMalformed: true);
    } else {
      return false;
    }
    final String lower = text.trimLeft().toLowerCase();
    if (lower.isEmpty || !lower.startsWith('{')) return false;
    return lower.contains('sensing_update') ||
        lower.contains('"classification"') ||
        lower.contains('"features"') ||
        lower.contains('"nodes"');
  }

  /// يتحقق من المرشّحين المفتوحين بمصافحة WebSocket حقيقية (بالتوازي).
  Future<List<LanCandidate>> verifyCandidates(
    List<LanCandidate> candidates, {
    int? limit,
  }) async {
    final List<int> pending = <int>[
      for (int i = 0; i < candidates.length; i++)
        if (!candidates[i].looksLikeRuView && !candidates[i].verified) i,
    ];
    if (pending.isEmpty) return candidates;

    pending.sort((int a, int b) =>
        candidates[b].score.compareTo(candidates[a].score));
    final List<int> selected =
        pending.take(limit ?? maxVerifications).toList(growable: false);

    final Map<int, bool> results = <int, bool>{};
    await Future.wait<void>(<Future<void>>[
      for (final int index in selected)
        verifySensing(candidates[index].host, candidates[index].port)
            .then<void>((bool ok) {
          results[index] = ok;
        }),
    ]);

    final List<LanCandidate> updated = List<LanCandidate>.from(candidates);
    results.forEach((int index, bool ok) {
      if (ok) updated[index] = updated[index].copyWith(verified: true);
    });
    return updated;
  }

  /// مسح كامل. يعيد المرشّحين مرتبين بالأفضلية.
  Future<List<LanCandidate>> scan({
    required NetworkContext context,
    Set<String> savedHosts = const <String>{},
    bool deep = false,
  }) async {
    if (!context.isConnected) return const <LanCandidate>[];

    // البثّ يعمل بالتوازي مع المسح ليلتقط البوابات المُعلنة فورًا.
    final Future<List<LanCandidate>> broadcast = useBroadcast
        ? broadcastProbe(context: context)
        : Future<List<LanCandidate>>.value(const <LanCandidate>[]);

    final Stopwatch watch = Stopwatch()..start();
    final List<String> hosts = hostsFor(
      context,
      deep: deep,
      extra: savedHosts,
    );
    final List<LanCandidate> found = <LanCandidate>[];
    final Set<String> probedHosts = <String>{};
    int probes = 0;

    // كل (مضيف، منفذ) كهدف مستقل: المنافذ تُفحص بالتوازي أيضًا.
    final List<({String host, int port})> targets =
        <({String host, int port})>[
      for (final String host in hosts)
        for (final int port in ports) (host: host, port: port),
    ];

    for (int index = 0; index < targets.length; index += concurrency) {
      if (watch.elapsed > maxScanDuration) break;
      final int end = math.min(index + concurrency, targets.length);
      final List<({String host, int port})> batch =
          targets.sublist(index, end);

      probes += batch.length;
      probedHosts.addAll(batch.map((({String host, int port}) t) => t.host));
      final List<Future<void>> tasks = <Future<void>>[];
      for (final ({String host, int port}) target in batch) {
        tasks.add(
          probe(
            target.host,
            target.port,
            isGateway: context.gatewayHosts.contains(target.host),
            isSaved: savedHosts.contains(target.host),
          ).then((LanCandidate? candidate) {
            if (candidate != null) found.add(candidate);
          }),
        );
      }
      await Future.wait<void>(tasks);

      // توقّف مبكر: وجدنا خادم RuView — لا داعي لإكمال بقية الشبكة.
      if (found.any((LanCandidate candidate) => candidate.isGatewayCandidate)) {
        break;
      }
    }

    // إن حسمنا الخادم من فحص TCP فلا داعي لانتظار مهلة البثّ كلها؛
    // البثّ يبقى مفيدًا فقط عندما لا نعرف هوية أي خادم (عزل عملاء مثلًا).
    final List<LanCandidate> announced =
        found.any((LanCandidate candidate) => candidate.isGatewayCandidate)
            ? const <LanCandidate>[]
            : await broadcast;
    List<LanCandidate> all = <LanCandidate>[...found];
    for (final LanCandidate candidate in announced) {
      final bool exists = all.any(
        (LanCandidate other) =>
            other.host == candidate.host && other.port == candidate.port,
      );
      if (!exists) all.add(candidate);
    }

    // التحقق القاطع: منفذ مفتوح ≠ بوابة RuView. نفتح WebSocket حقيقيًا
    // وننتظر إطار استشعار، فلا تُعرض «بوابة» وهمية أبدًا.
    all = await verifyCandidates(all);

    final LanScanReport report = LanScanReport(
      networkLabel: context.label,
      hostsScanned: probedHosts.length,
      portsScanned: ports.length,
      probes: probes,
      openPorts: all.where((LanCandidate c) => !c.isGatewayCandidate).length,
      gateways: all.where((LanCandidate c) => c.isGatewayCandidate).length,
      durationMs: watch.elapsedMilliseconds,
      deep: deep,
    );
    lastReport = report;
    return ranked(all);
  }

  /// بصمة خادم RuView من جسم الرد.
  ///
  /// لا يكفي أن يردّ المنفذ `200` (أي لوحة راوتر أو صفحة ويب تفعل ذلك)، ولا
  /// مجرّد ورود كلمة «sensing» في صفحة HTML. نطلب أثرًا من JSON الخاص بـ
  /// RuView أو من ترقية WebSocket فعلية.
  static bool _looksLikeRuViewBody(String text) {
    if (text.contains('sensing_update')) return true;
    if (text.contains('subcarrier')) return true;
    if (text.contains('101 switching protocols')) return true;
    // مفاتيح JSON مثل "service":"ruview-gateway" أو {"ruview":true}
    if (text.contains('"ruview')) return true;
    if (text.contains('sensing_path')) return true;
    if (text.contains('ws/sensing')) return true;
    return false;
  }

  /// بثّ UDP للاكتشاف على منفذ [discoveryPort].
  ///
  /// البوابة التي تفهم البروتوكول تردّ بـ JSON:
  /// `{"type":"ruview_gateway","host":"192.168.1.1","port":3000}`
  /// وهذا يعمل حتى لو كان الراوتر يحجب مسح المنافذ (AP Isolation).
  Future<List<LanCandidate>> broadcastProbe({
    required NetworkContext context,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    if (!context.isConnected) return const <LanCandidate>[];

    final List<LanCandidate> candidates = <LanCandidate>[];
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      final List<int> payload = utf8.encode(
        jsonEncode(<String, dynamic>{
          'type': 'ruview_discovery',
          'magic': discoveryMagic,
          'app': 'ruview-wifi',
        }),
      );

      final Set<String> targets = <String>{
        '255.255.255.255',
        for (final String prefix in context.prefixes) '$prefix.255',
      };
      for (final String target in targets) {
        final InternetAddress? address = InternetAddress.tryParse(target);
        if (address == null) continue;
        try {
          socket.send(payload, address, discoveryPort);
        } catch (_) {
          // بعض الشبكات تمنع البثّ المُوجّه — نتجاهل ونتابع.
        }
      }

      subscription = socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final Datagram? datagram = socket?.receive();
        if (datagram == null) return;
        final LanCandidate? candidate = candidateFromDiscovery(
          utf8.decode(datagram.data, allowMalformed: true),
          datagram.address.address,
        );
        if (candidate != null) candidates.add(candidate);
      });

      await Future<void>.delayed(timeout);
    } catch (_) {
      // لا بثّ (منصّة/إذن) — المسح العادي يكفي.
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
    return ranked(candidates);
  }

  /// يحوّل ردّ بثّ إلى مرشّح (دالة نقية تُختبر مباشرة).
  static LanCandidate? candidateFromDiscovery(
    String payload,
    String fallbackHost,
  ) {
    final String text = payload.trim();
    if (text.isEmpty || !text.toLowerCase().contains('ruview')) return null;

    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) {
        final Object? rawPort = decoded['port'];
        final int port = rawPort is num ? rawPort.toInt() : 3000;
        final Object? rawHost = decoded['host'];
        final String host = rawHost is String && rawHost.isNotEmpty
            ? rawHost
            : fallbackHost;
        if (host.isEmpty || port <= 0 || port > 65535) return null;
        return LanCandidate(
          host: host,
          port: port,
          latencyMs: 0,
          looksLikeRuView: true,
          source: 'بثّ',
        );
      }
    } catch (_) {
      // ردّ غير JSON لكنه يذكر RuView — نقبله على المنفذ الافتراضي.
    }
    return LanCandidate(
      host: fallbackHost,
      port: 3000,
      latencyMs: 0,
      looksLikeRuView: true,
      source: 'بثّ',
    );
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
