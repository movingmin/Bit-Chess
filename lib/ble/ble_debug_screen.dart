import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'transport.dart';

/// 2단계 BLE 기술 검증 화면(디버그 빌드 전용). 케이블 없는 폰도 이 화면만 보고 판정한다.
class BleDebugScreen extends StatefulWidget {
  const BleDebugScreen({super.key});

  @override
  State<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _Log {
  _Log(this.time, this.text, this.color);
  final DateTime time;
  final String text;
  final Color color;
}

class _BleDebugScreenState extends State<BleDebugScreen> {
  final Transport t = transport;
  final _clock = Stopwatch()..start(); // 단조 시계(왕복 시간용)
  final _rooms = <String, Room>{};
  final _logs = <_Log>[];
  late final StreamSubscription<TransportEvent> _sub;

  String? _blocker; // 권한·블루투스 안내
  String _state = '대기';
  bool _connected = false;
  int _seq = 0;
  int _pingsSent = 0, _pongs = 0;
  String? _sentHash;
  String _hashResult = '-';

  @override
  void initState() {
    super.initState();
    _sub = t.events.listen(_onEvent);
    _check();
  }

  @override
  void dispose() {
    _sub.cancel();
    t.stop();
    super.dispose();
  }

  Future<bool> _check() async {
    String? b;
    if (!await t.ensurePermissions()) {
      b =
          '근처 기기(블루투스) 권한이 필요합니다.\n'
          '[권한 다시 요청]을 누르거나, 설정 → 애플리케이션 → Bit-Chess → 권한 → "근처 기기"를 허용하세요.';
    } else if (!await t.bluetoothOn()) {
      b = '블루투스가 꺼져 있습니다.\n빠른 설정에서 블루투스를 켜세요. 비행기 모드여도 블루투스는 켤 수 있습니다.';
    }
    setState(() => _blocker = b);
    return b == null;
  }

  void _log(String s, [Color c = Colors.white]) => setState(() => _logs.insert(0, _Log(DateTime.now(), s, c)));

  static String _short(List<int> bytes) => sha256.convert(bytes).toString().substring(0, 8);

  void _onEvent(TransportEvent e) {
    switch (e) {
      case BluetoothState(:final on):
        _log('블루투스 ${on ? '켜짐' : '꺼짐'}', on ? Colors.white : Colors.orange);
        if (!on) setState(() => _connected = false);
        _check();
      case RoomFound(:final room):
        final isNew = !_rooms.containsKey(room.idHex);
        setState(() => _rooms[room.idHex] = room);
        if (isNew) _log('방 발견: ${room.name} (#${room.idHex}, ${room.rssi} dBm)');
      case Connected(:final role, :final mtu):
        setState(() {
          _connected = true;
          _state = '연결됨 (${role == 'host' ? '호스트' : '게스트'}, MTU $mtu)';
          _rooms.clear();
        });
        _log('연결됨: $role, MTU $mtu', Colors.greenAccent);
      case Disconnected(:final status):
        setState(() {
          _connected = false;
          _state = '끊김';
        });
        _log('연결 끊김 (status $status)', Colors.orange);
      case MessageReceived(:final bytes):
        _onMessage(bytes);
      case TransportLog(:final msg, :final error):
        _log(msg, error ? Colors.redAccent : Colors.white70);
    }
  }

  Future<void> _send(Map<String, Object?> m) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'ver': 1, 'seq': ++_seq, ...m})));
    try {
      await t.send(bytes);
    } on Object catch (e) {
      _log('보내기 실패: $e', Colors.redAccent);
    }
  }

  void _onMessage(Uint8List bytes) {
    final Map<String, Object?> m;
    try {
      m = (jsonDecode(utf8.decode(bytes)) as Map).cast();
    } on Object {
      _log('형식 오류 메시지 ${bytes.length}B', Colors.redAccent);
      return;
    }
    switch (m['type']) {
      case 'PING':
        _log('PING 받음 (#${m['seq']})');
        _send({'type': 'PONG', 't': m['t']});
      case 'PONG':
        final rtt = (_clock.elapsedMicroseconds - (m['t'] as int)) / 1000;
        setState(() => _pongs++);
        _log('PONG 받음: 왕복 ${rtt.toStringAsFixed(0)} ms', Colors.greenAccent);
      case 'TEST':
        final data = base64Decode(m['data'] as String);
        final h = _short(data);
        _log('2KB 받음: ${data.length}B, SHA-256 $h (전체 메시지 ${bytes.length}B)', Colors.lightBlueAccent);
        _send({'type': 'TEST_ACK', 'hash': h});
      case 'TEST_ACK':
        final ok = m['hash'] == _sentHash;
        setState(() => _hashResult = ok ? '일치 ($_sentHash)' : '불일치!');
        _log('상대 해시 ${m['hash']} → ${ok ? '일치' : '불일치'}', ok ? Colors.greenAccent : Colors.redAccent);
      default:
        _log('알 수 없는 메시지: ${m['type']}', Colors.orange);
    }
  }

  Future<void> _ping() async {
    setState(() => _pingsSent++);
    _log('PING 보냄');
    await _send({'type': 'PING', 't': _clock.elapsedMicroseconds});
  }

  Future<void> _test2k() async {
    final r = Random.secure();
    final data = Uint8List.fromList(List.generate(2048, (_) => r.nextInt(256)));
    _sentHash = _short(data);
    setState(() => _hashResult = '대기');
    _log('2KB 보냄: SHA-256 $_sentHash', Colors.lightBlueAccent);
    await _send({'type': 'TEST', 'data': base64Encode(data)});
  }

  Future<void> _run(Future<void> Function() f) async {
    if (!await _check()) return;
    try {
      await f();
    } on Object catch (e) {
      _log('$e', Colors.redAccent);
    }
  }

  Widget _btn(String label, VoidCallback? onTap) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
      ),
    ),
  );

  String _hhmmss(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}.${(d.millisecond ~/ 10).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BLE 테스트 (디버그)')),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_blocker != null)
            Container(
              color: Colors.orange.shade900,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(_blocker!, style: const TextStyle(fontSize: 16)),
                  TextButton(onPressed: _check, child: const Text('권한 다시 요청 / 다시 확인')),
                ],
              ),
            ),
          Container(
            color: _connected ? Colors.green.shade800 : Colors.grey.shade800,
            padding: const EdgeInsets.all(12),
            child: Text(
              '상태: $_state\nping 성공 $_pongs/$_pingsSent   ·   2KB 해시: $_hashResult',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Row(
            children: [
              _btn(
                '방 열기',
                _connected
                    ? null
                    : () => _run(() async {
                        await t.startHost('BLE 테스트');
                        setState(() => _state = '방 열림 (기다리는 중)');
                      }),
              ),
              _btn(
                '방 찾기',
                _connected
                    ? null
                    : () => _run(() async {
                        setState(_rooms.clear);
                        await t.startScan();
                        setState(() => _state = '찾는 중');
                      }),
              ),
              _btn('연결 끊기', _connected ? () => _run(t.disconnect) : null),
            ],
          ),
          Row(
            children: [
              _btn('ping', _connected ? () => _run(_ping) : null),
              _btn('2KB 보내기', _connected ? () => _run(_test2k) : null),
              _btn(
                '로그 지우기',
                () => setState(() {
                  _logs.clear();
                  _pingsSent = _pongs = 0;
                  _hashResult = '-';
                }),
              ),
            ],
          ),
          for (final r in _rooms.values)
            ListTile(
              tileColor: Colors.blueGrey.shade900,
              title: Text('${r.name}  #${r.idHex}', style: const TextStyle(fontSize: 18)),
              subtitle: Text('신호 ${r.rssi} dBm · 눌러서 연결'),
              onTap: () => _run(() => t.connect(r)),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (_, i) {
                final l = _logs[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text('${_hhmmss(l.time)}  ${l.text}', style: TextStyle(fontSize: 15, color: l.color)),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
