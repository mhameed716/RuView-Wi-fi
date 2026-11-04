import 'dart:io';

/// بروتوكول النقل المدعوم للاتصال ببوابة RuView.
enum TransportKind {
  /// بث JSON الحي من `/ws/sensing` — يُفضّل دائمًا عند توفّره.
  webSocket('WebSocket', '/ws/sensing'),

  /// استقبال حزم UDP مباشرة من عقد ESP32 (منفذ 5005 افتراضيًا).
  udp('UDP', ''),

  /// مصدر محاكاة يعمل داخل التطبيق بلا شبكة — للتجربة وإثبات سلامة الخط.
  simulator('محاكاة', '');

  const TransportKind(this.label, this.defaultPath);

  final String label;

  /// المسار الافتراضي في حالة WebSocket.
  final String defaultPath;

  static TransportKind fromName(String? name) => switch (name) {
        'udp' => TransportKind.udp,
        'simulator' => TransportKind.simulator,
        _ => TransportKind.webSocket,
      };

  String get storageName => switch (this) {
        TransportKind.udp => 'udp',
        TransportKind.simulator => 'simulator',
        TransportKind.webSocket => 'websocket',
      };

  /// هل هذا مصدر داخلي (محاكاة) لا يحتاج شبكة؟
  bool get isSimulator => this == TransportKind.simulator;

  /// هل يحتاج عنوانًا ومنفذًا صالحين؟
  bool get needsEndpoint => !isSimulator;
}

/// إعدادات الاتصال ببوابة RuView (تُحفظ محليًا على الجهاز).
class ConnectionSettings {
  const ConnectionSettings({
    this.host = '192.168.1.100',
    this.port = 8765,
    this.transport = TransportKind.webSocket,
    this.authToken = '',
    this.secure = false,
    this.ipAddress = '',
  });

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) {
    return ConnectionSettings(
      host: (json['host'] as String?)?.trim() ?? '192.168.1.100',
      port: (json['port'] as num?)?.toInt() ?? 8765,
      transport: TransportKind.fromName(json['transport'] as String?),
      authToken: (json['auth_token'] as String?) ?? '',
      secure: json['secure'] == true,
      ipAddress: (json['ip_address'] as String?) ?? '',
    );
  }

  /// عنوان البوابة: IP أو اسم مضيف، بدون مخطط (scheme) أو مسار.
  final String host;

  /// منفذ WebSocket أو منفذ UDP حسب النوع.
  final int port;

  final TransportKind transport;

  /// رمز الوصول (Bearer) عند تفعيل المصادقة على الخادم — ADR-272.
  final String authToken;

  /// اتصال WebSocket مشفّر (wss).
  final bool secure;

  /// آخر عنوان IP محلي لجهاز الهاتف (للعرض والإرشاد فقط).
  final String ipAddress;

  ConnectionSettings copyWith({
    String? host,
    int? port,
    TransportKind? transport,
    String? authToken,
    bool? secure,
    String? ipAddress,
  }) {
    return ConnectionSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      transport: transport ?? this.transport,
      authToken: authToken ?? this.authToken,
      secure: secure ?? this.secure,
      ipAddress: ipAddress ?? this.ipAddress,
    );
  }

  /// مسار WebSocket الكامل.
  String get wsPath => transport.defaultPath;

  /// رابط WebSocket النهائي مع رمز الوصول (إن وُجد) كـ query غير حساس.
  Uri? get webSocketUri {
    if (!isValid || !transport.needsEndpoint) return null;
    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: host,
      port: port,
      path: wsPath,
    );
  }

  /// ترويسات المصادقة — العملاء الأصليون (Native) يمكنهم إرسال Bearer على
  /// ترقية WebSocket مباشرة، بخلاف المتصفحات (ADR-272).
  Map<String, String> get authHeaders {
    final String token = authToken.trim();
    if (token.isEmpty) return const <String, String>{};
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  bool get hasToken => authToken.trim().isNotEmpty;

  /// هل العنوان صالح؟ (IPv4 / اسم مضيف / IPv6 محاط بأقواس)
  bool get isValidHost {
    final String value = host.trim();
    if (value.isEmpty) return false;
    if (value.contains(' ')) return false;
    if (value.contains('/')) return false;
    if (value.contains('://')) return false;
    if (InternetAddress.tryParse(value) != null) return true;
    // اسم مضيف: أحرف/أرقام/نقاط/شرطات فقط
    return RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.\-]{0,251}[a-zA-Z0-9])?$')
        .hasMatch(value);
  }

  bool get isValidPort => port >= 1 && port <= 65535;

  /// صالح للاتصال: المحاكاة لا تحتاج مضيفًا، والبقية تحتاج عنوانًا ومنفذًا.
  bool get isValid => transport.needsEndpoint
      ? (isValidHost && isValidPort)
      : true;

  /// وصف مختصر يُعرض في شرائح الحالة: `192.168.1.50:8765`.
  String get endpointLabel => transport.isSimulator
      ? 'مصدر داخلي (محاكاة)'
      : '${host.trim()}:$port';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'port': port,
        'transport': transport.storageName,
        'auth_token': authToken,
        'secure': secure,
        'ip_address': ipAddress,
      };

  @override
  bool operator ==(Object other) =>
      other is ConnectionSettings &&
      other.host == host &&
      other.port == port &&
      other.transport == transport &&
      other.authToken == authToken &&
      other.secure == secure;

  @override
  int get hashCode => Object.hash(host, port, transport, authToken, secure);

  @override
  String toString() => 'ConnectionSettings($endpointLabel, ${transport.label})';
}
