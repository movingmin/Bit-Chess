import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'framing.dart';

/// 주변에서 찾은 방.
class Room {
  Room(this.address, this.roomId, this.name, this.rssi);
  final String address; // 연결용 내부 값. 화면·로그에는 쓰지 않는다
  final Uint8List roomId;
  final String name;
  final int rssi;
  String get idHex => roomId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

sealed class TransportEvent {}

class BluetoothState extends TransportEvent {
  BluetoothState(this.on);
  final bool on;
}

class RoomFound extends TransportEvent {
  RoomFound(this.room);
  final Room room;
}

class Connected extends TransportEvent {
  Connected(this.role, this.mtu);
  final String role; // host / guest
  final int mtu;
}

class Disconnected extends TransportEvent {
  Disconnected(this.status);
  final int status;
}

/// 다 합쳐진 메시지 하나.
class MessageReceived extends TransportEvent {
  MessageReceived(this.bytes);
  final Uint8List bytes;
}

class TransportLog extends TransportEvent {
  TransportLog(this.msg, {this.error = false});
  final String msg;
  final bool error;
}

/// BLE 1:1 연결. 플랫폼별 구현(Android: [AndroidTransport], iOS: 나중에)을 숨긴다.
/// 앱 전체에 하나. 네이티브 이벤트 채널은 리스너를 하나만 둔다.
final Transport transport = AndroidTransport();

abstract class Transport {
  Stream<TransportEvent> get events;
  Future<bool> bluetoothOn();
  Future<bool> ensurePermissions();

  /// 권한 창 없이 현재 상태만 확인.
  Future<bool> hasPermissions();

  /// 앱 설정 화면(권한)을 연다. 두 번 거부하면 Android가 권한 창을 더 띄우지 않으므로 필요하다.
  Future<void> openAppSettings();
  Future<void> startHost(String roomName);
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(Room room);

  /// 메시지 하나를 보낸다(쪼개기는 구현이 한다).
  Future<void> send(Uint8List message);
  Future<void> disconnect();
  Future<void> stop();
}

class AndroidTransport implements Transport {
  AndroidTransport() {
    _events.receiveBroadcastStream().listen(_onNative);
  }

  static const _m = MethodChannel('bitchess/ble');
  static const _events = EventChannel('bitchess/ble/events');
  final _out = StreamController<TransportEvent>.broadcast();
  final _rand = Random.secure();
  var _reasm = Reassembler();
  int _chunk = 20; // MTU 23 - 3
  int _msgId = 0;

  @override
  Stream<TransportEvent> get events => _out.stream;

  void _onNative(dynamic e) {
    final m = (e as Map).cast<String, Object?>();
    switch (m['type']) {
      case 'bluetooth':
        _out.add(BluetoothState(m['on'] as bool));
      case 'room':
        _out.add(
          RoomFound(Room(m['address'] as String, m['roomId'] as Uint8List, m['name'] as String, m['rssi'] as int)),
        );
      case 'connected':
        final mtu = m['mtu'] as int;
        _chunk = min(mtu - 3, 512);
        _reasm = Reassembler();
        _out.add(Connected(m['role'] as String, mtu));
      case 'disconnected':
        _out.add(Disconnected(m['status'] as int));
      case 'data':
        final msg = _reasm.add(m['bytes'] as Uint8List);
        if (msg != null) _out.add(MessageReceived(msg));
      case 'error':
        _out.add(TransportLog(m['msg'] as String, error: true));
      case 'log':
        _out.add(TransportLog(m['msg'] as String));
    }
  }

  @override
  Future<bool> bluetoothOn() async => await _m.invokeMethod<bool>('bluetoothOn') ?? false;

  @override
  Future<bool> ensurePermissions() async => await _m.invokeMethod<bool>('ensurePermissions') ?? false;

  @override
  Future<bool> hasPermissions() async => await _m.invokeMethod<bool>('hasPermissions') ?? false;

  @override
  Future<void> openAppSettings() => _m.invokeMethod('openAppSettings');

  @override
  Future<void> startHost(String roomName) => _m.invokeMethod('startHost', {
    'roomId': Uint8List.fromList(List.generate(4, (_) => _rand.nextInt(256))), // 세션마다 새로
    'name': roomName,
  });

  @override
  Future<void> startScan() => _m.invokeMethod('startScan');

  @override
  Future<void> stopScan() => _m.invokeMethod('stopScan');

  @override
  Future<void> connect(Room room) => _m.invokeMethod('connect', room.address);

  @override
  Future<void> send(Uint8List message) async {
    _msgId = (_msgId + 1) & 0xFF;
    for (final c in split(message, _msgId, _chunk)) {
      await _m.invokeMethod('send', c);
    }
  }

  @override
  Future<void> disconnect() => _m.invokeMethod('disconnect');

  @override
  Future<void> stop() => _m.invokeMethod('stop');
}
