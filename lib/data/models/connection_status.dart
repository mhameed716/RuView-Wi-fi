import '../../core/l10n/ar_strings.dart';

/// حالة الاتصال ببوابة RuView — تُعرض في الواجهة كمؤشر حي.
enum ConnectionStatus {
  disconnected(ArStrings.statusDisconnected),
  connecting(ArStrings.statusConnecting),
  connected(ArStrings.statusConnected),
  reconnecting(ArStrings.statusReconnecting),
  error(ArStrings.statusError);

  const ConnectionStatus(this.arabicLabel);

  final String arabicLabel;

  bool get isBusy =>
      this == ConnectionStatus.connecting || this == ConnectionStatus.reconnecting;

  bool get isLive => this == ConnectionStatus.connected;

  bool get hasError => this == ConnectionStatus.error;
}

/// حدث ينقل حزمة بيانات أو تغيّر حالة من طبقة النقل إلى طبقة العرض.
class TransportEvent {
  const TransportEvent._({
    required this.kind,
    this.frame,
    this.message,
    this.retryIn,
    this.attempt,
  });

  factory TransportEvent.connecting() =>
      const TransportEvent._(kind: TransportEventKind.connecting);

  factory TransportEvent.connected({String? message}) => TransportEvent._(
        kind: TransportEventKind.connected,
        message: message,
      );

  factory TransportEvent.data(Object frame) => TransportEvent._(
        kind: TransportEventKind.frame,
        frame: frame,
      );

  factory TransportEvent.disconnected({String? message}) => TransportEvent._(
        kind: TransportEventKind.disconnected,
        message: message,
      );

  factory TransportEvent.reconnecting({
    required Duration retryIn,
    required int attempt,
    String? message,
  }) =>
      TransportEvent._(
        kind: TransportEventKind.reconnecting,
        retryIn: retryIn,
        attempt: attempt,
        message: message,
      );

  factory TransportEvent.failed(String message) => TransportEvent._(
        kind: TransportEventKind.error,
        message: message,
      );

  final TransportEventKind kind;
  final Object? frame;
  final String? message;
  final Duration? retryIn;
  final int? attempt;
}

/// أنواع أحداث طبقة النقل.
enum TransportEventKind { connecting, connected, frame, disconnected, reconnecting, error }
