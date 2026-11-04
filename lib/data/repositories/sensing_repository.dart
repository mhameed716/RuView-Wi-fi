import 'dart:async';

import '../models/connection_settings.dart';
import '../models/connection_status.dart';
import '../models/json_read.dart';
import '../models/sensing_frame.dart';
import '../services/local_sensing_transport.dart';
import '../services/sensing_transport.dart';
import '../services/udp_sensing_transport.dart';
import '../services/websocket_sensing_transport.dart';

/// لقطة حالة اتصال تُبثّ إلى طبقة العرض.
class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.status,
    this.message,
    this.retryIn,
    this.attempt = 0,
  });

  final ConnectionStatus status;
  final String? message;
  final Duration? retryIn;
  final int attempt;
}

/// مصدر بيانات الاستشعار (واجهة) — يسمح للـ ViewModels بالاعتماد على تجريد
/// بسيط، ويجعل اختبارها ممكنًا دون شبكة أو مقابس.
abstract class SensingDataSource {
  /// بث إطارات الاستشعار بعد تحويلها إلى نماذج مجال.
  Stream<SensingFrame> get frames;

  /// بث تغيّرات حالة الاتصال.
  Stream<ConnectionSnapshot> get connection;
}

/// مستودع الاستشعار: يملك طبقة النقل، يحوّل الحزم إلى نماذج مجال، ويبثّ
/// الإطارات وحالة الاتصال إلى الـ ViewModels.
///
/// هذا الفصل يجعل الـ ViewModels مستقلة تمامًا عن `dart:io` ويسهّل الاختبار.
class SensingRepository implements SensingDataSource {
  SensingRepository({
    SensingTransport Function(ConnectionSettings settings)? transportFactory,
  }) : _transportFactory = transportFactory ?? _defaultTransportFactory;

  final SensingTransport Function(ConnectionSettings settings) _transportFactory;

  final StreamController<SensingFrame> _frames =
      StreamController<SensingFrame>.broadcast();
  final StreamController<ConnectionSnapshot> _connection =
      StreamController<ConnectionSnapshot>.broadcast();

  SensingTransport? _transport;
  StreamSubscription<TransportEvent>? _subscription;
  ConnectionSnapshot _snapshot =
      const ConnectionSnapshot(status: ConnectionStatus.disconnected);
  ConnectionSettings? _settings;
  bool _disposed = false;
  int _frameCount = 0;
  DateTime? _lastFrameAt;

  @override
  Stream<SensingFrame> get frames => _frames.stream;

  @override
  Stream<ConnectionSnapshot> get connection => _connection.stream;

  ConnectionSnapshot get snapshot => _snapshot;

  ConnectionSettings? get settings => _settings;

  int get frameCount => _frameCount;

  DateTime? get lastFrameAt => _lastFrameAt;

  static SensingTransport _defaultTransportFactory(
    ConnectionSettings settings,
  ) {
    return switch (settings.transport) {
      TransportKind.udp => UdpSensingTransport(),
      TransportKind.simulator => LocalSensingTransport(),
      TransportKind.webSocket => WebSocketSensingTransport(),
    };
  }

  /// الاتصال بالبوابة باستخدام الإعدادات المعطاة.
  Future<void> connect(ConnectionSettings settings) async {
    if (_disposed) return;
    await _detachTransport(notify: false);

    _settings = settings;
    _frameCount = 0;
    _lastFrameAt = null;

    final SensingTransport transport = _transportFactory(settings);
    _transport = transport;
    _subscription = transport.events.listen(_handleTransportEvent);
    _emit(const ConnectionSnapshot(status: ConnectionStatus.connecting));

    try {
      await transport.connect(settings);
    } catch (error) {
      _emit(
        ConnectionSnapshot(
          status: ConnectionStatus.error,
          message: 'تعذّر بدء الاتصال: $error',
        ),
      );
    }
  }

  /// قطع الاتصال بإرادة المستخدم (يمنع إعادة المحاولة التلقائية).
  Future<void> disconnect() async {
    final SensingTransport? transport = _transport;
    if (transport != null) {
      await transport.disconnect();
    }
    await _detachTransport(notify: false);
    _emit(const ConnectionSnapshot(status: ConnectionStatus.disconnected));
  }

  void _handleTransportEvent(TransportEvent event) {
    switch (event.kind) {
      case TransportEventKind.connecting:
        _emit(const ConnectionSnapshot(status: ConnectionStatus.connecting));
      case TransportEventKind.connected:
        _emit(
          ConnectionSnapshot(
            status: ConnectionStatus.connected,
            message: event.message,
          ),
        );
      case TransportEventKind.frame:
        _handleFramePayload(event.frame);
      case TransportEventKind.reconnecting:
        _emit(
          ConnectionSnapshot(
            status: ConnectionStatus.reconnecting,
            message: event.message,
            retryIn: event.retryIn,
            attempt: event.attempt ?? 0,
          ),
        );
      case TransportEventKind.disconnected:
        _emit(
          ConnectionSnapshot(
            status: ConnectionStatus.disconnected,
            message: event.message,
          ),
        );
      case TransportEventKind.error:
        _emit(
          ConnectionSnapshot(
            status: ConnectionStatus.error,
            message: event.message,
          ),
        );
    }
  }

  void _handleFramePayload(Object? payload) {
    if (payload is! Map<String, dynamic>) return;
    try {
      // نتجاهل الرسائل الإدارية التي لا تحمل بيانات استشعار.
      final String type = JsonRead.asString(payload['type'], 'sensing_update');
      final bool looksLikeSensing = type == 'sensing_update' ||
          payload.containsKey('classification') ||
          payload.containsKey('nodes') ||
          payload.containsKey('features');
      if (!looksLikeSensing) return;

      final SensingFrame frame = SensingFrame.fromJson(payload);
      _frameCount++;
      _lastFrameAt = frame.receivedAt;

      // أول إطار يرفع الحالة إلى "متصل" حتى لو تأخّر حدث الفتح.
      if (_snapshot.status != ConnectionStatus.connected) {
        _emit(
          ConnectionSnapshot(
            status: ConnectionStatus.connected,
            message: _settings?.endpointLabel,
          ),
        );
      }

      if (!_frames.isClosed) {
        _frames.add(frame);
      }
    } catch (_) {
      // إطار تالف لا يجب أن يُسقط الجلسة.
    }
  }

  Future<void> _detachTransport({required bool notify}) async {
    final StreamSubscription<TransportEvent>? subscription = _subscription;
    _subscription = null;
    final SensingTransport? transport = _transport;
    _transport = null;
    // نبدأ التحرير فورًا (يوقف مؤقّتات النقل ويسدّ مقابسه) ثم ننتظر الاثنين:
    // انتظار إلغاء الاشتراك أولًا كان يُبقي المؤقّتات حيّة لحظات إضافية.
    final Future<void> disposal =
        transport == null ? Future<void>.value() : transport.dispose();
    await subscription?.cancel();
    await disposal;
    if (notify) {
      _emit(const ConnectionSnapshot(status: ConnectionStatus.disconnected));
    }
  }

  void _emit(ConnectionSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_connection.isClosed) {
      _connection.add(snapshot);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _detachTransport(notify: false);
    await _frames.close();
    await _connection.close();
  }
}
