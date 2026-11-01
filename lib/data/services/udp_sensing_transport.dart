import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/connection_settings.dart';
import '../models/connection_status.dart';
import 'csi_analyzer.dart';
import 'sensing_transport.dart';

/// مستقبل UDP مباشر من عُقد ESP32 (المنفذ الافتراضي 5005).
///
/// يدعم صيغتين على نفس المقبس:
///  1. حزم CSI ثنائية بصيغة ADR-018 (تُحلَّل محليًا عبر [CsiAnalyzer]).
///  2. رسائل JSON بصيغة `sensing_update` من بوابة وسيطة.
///
/// ملاحظة: UDP بلا اتصال (connectionless)، لذا "متصل" هنا تعني *يستمع بنجاح*
/// وليست ضمانًا لوصول البيانات؛ تتولّى طبقة العرض كشف توقف البيانات.
class UdpSensingTransport implements SensingTransport {
  UdpSensingTransport({CsiAnalyzer? analyzer}) : _analyzer = analyzer ?? CsiAnalyzer();

  final CsiAnalyzer _analyzer;
  final StreamController<TransportEvent> _events =
      StreamController<TransportEvent>.broadcast();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _disposed = false;
  ConnectionSettings? _settings;

  int get receivedPackets => _analyzer.packetCount;

  @override
  Stream<TransportEvent> get events => _events.stream;

  @override
  bool get isActive => _socket != null;

  @override
  Future<void> connect(ConnectionSettings settings) async {
    await _closeSocket(silent: true);
    _settings = settings;
    _analyzer.reset();
    _emit(TransportEvent.connecting());

    try {
      final RawDatagramSocket socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        settings.port,
        reuseAddress: true,
      );
      if (_disposed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _socket = socket;
      _subscription = socket.listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          _emit(TransportEvent.failed(_humanize(error, settings.port)));
        },
        onDone: () {
          if (!_disposed) {
            _emit(TransportEvent.disconnected(message: 'أُغلق مقبس UDP'));
          }
        },
        cancelOnError: false,
      );
      _emit(
        TransportEvent.connected(
          message: 'الاستماع على المنفذ ${settings.port}',
        ),
      );
    } on SocketException catch (error) {
      _emit(TransportEvent.failed(_humanize(error, settings.port)));
    } catch (error) {
      _emit(TransportEvent.failed(_humanize(error, settings.port)));
    }
  }

  void _handleEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final RawDatagramSocket? socket = _socket;
    if (socket == null) return;

    Datagram? datagram = socket.receive();
    while (datagram != null) {
      _handleDatagram(datagram.data);
      datagram = socket.receive();
    }
  }

  void _handleDatagram(Uint8List data) {
    if (data.isEmpty) return;

    // رسالة JSON من بوابة وسيطة؟
    if (data.length > 2 && data[0] == 0x7B /* { */) {
      try {
        final Object? decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map<String, dynamic>) {
          _emit(TransportEvent.data(decoded));
          return;
        }
      } catch (_) {
        // ليست JSON صالحة — جرّب صيغة CSI.
      }
    }

    final Map<String, dynamic>? update = _analyzer.ingest(data);
    if (update != null) {
      _emit(TransportEvent.data(update));
    }
  }

  @override
  Future<void> disconnect() async {
    await _closeSocket(silent: false);
    _emit(TransportEvent.disconnected());
  }

  Future<void> _closeSocket({required bool silent}) async {
    await _subscription?.cancel();
    _subscription = null;
    final RawDatagramSocket? socket = _socket;
    _socket = null;
    socket?.close();
    if (silent) {
      // لا نُصدر حدثًا؛ الاستدعاء من داخل connect.
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _closeSocket(silent: true);
    await _events.close();
  }

  void _emit(TransportEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  static String _humanize(Object error, int port) {
    if (error is SocketException) {
      final String detail = error.osError?.message ?? error.message;
      if (detail.toLowerCase().contains('address already in use') ||
          detail.contains('98')) {
        return 'المنفذ $port مستخدم بالفعل — أغلق التطبيق الآخر أو غيّر المنفذ';
      }
      if (detail.toLowerCase().contains('permission')) {
        return 'لا توجد صلاحية لفتح المنفذ $port — جرّب منفذًا أعلى من 1024';
      }
      return 'تعذّر فتح منفذ UDP $port — $detail';
    }
    return 'خطأ في مقبس UDP: $error';
  }
}
