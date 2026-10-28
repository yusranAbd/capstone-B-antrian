import 'dart:async';

import '../../../config.dart';
import '../models/staff_queue_models.dart';

sealed class StaffQueueEvent {
  @override
  String toString() => runtimeType.toString();
}

final class StaffSessionEnded extends StaffQueueEvent {}

final class StaffRealtimeStatus extends StaffQueueEvent {
  StaffRealtimeStatus(this.status);
  final String status;
}

final class StaffRefresh extends StaffQueueEvent {
  StaffRefresh({this.assignments = false});
  final bool assignments;
  final completion = Completer<void>();
}

final class StaffRoomSelected extends StaffQueueEvent {
  StaffRoomSelected(this.roomId);
  final String roomId;
}

final class StaffPageSelected extends StaffQueueEvent {
  StaffPageSelected(this.page);
  final int page;
}

/// QR is transient command input, redacted from diagnostics and consumed once.
final class StaffCommand extends StaffQueueEvent {
  StaffCommand(this.operation, {this.ticketId, String? qr}) {
    _qr = qr;
  }
  final StaffOperation operation;
  final String? ticketId;
  String? _qr;
  String? takeQr() {
    final value = _qr;
    _qr = null;
    return value;
  }

  final completion = Completer<Json>();
}
