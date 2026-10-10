import 'dart:typed_data';

/// 조각 헤더: 메시지 번호(1) + 조각 번호(2) + 조각 수(2).
const headerLen = 5;

/// 메시지를 [chunkSize] 바이트 이하 조각으로 나눈다(헤더 포함).
List<Uint8List> split(Uint8List msg, int msgId, int chunkSize) {
  final body = chunkSize - headerLen;
  if (body <= 0) throw ArgumentError('chunkSize too small: $chunkSize');
  final total = msg.isEmpty ? 1 : (msg.length + body - 1) ~/ body;
  if (total > 0xFFFF) throw ArgumentError('message too large');
  return [
    for (var i = 0; i < total; i++)
      (BytesBuilder(copy: false)
            ..add([msgId & 0xFF, i >> 8, i & 0xFF, total >> 8, total & 0xFF])
            ..add(Uint8List.sublistView(msg, i * body, ((i + 1) * body).clamp(0, msg.length))))
          .toBytes(),
  ];
}

/// 조각을 모아 완성된 메시지를 돌려준다. 순서가 섞여도 되고, 같은 조각이 두 번 와도 된다.
/// 조각이 빠진 메시지는 완성되지 않는다. 메시지 번호는 0~255를 돌아가며 쓰므로
/// 미완성 조각은 같은 번호가 다시 올 때(조각 수가 다르면 즉시, 같으면 덮어써짐) 정리된다.
class Reassembler {
  final _parts = <int, Map<int, Uint8List>>{};
  final _totals = <int, int>{};

  /// 완성되면 메시지, 아니면 null. 형식이 깨진 조각은 무시한다.
  Uint8List? add(Uint8List chunk) {
    if (chunk.length < headerLen) return null;
    final id = chunk[0], idx = chunk[1] << 8 | chunk[2], total = chunk[3] << 8 | chunk[4];
    if (total == 0 || idx >= total) return null;
    if (_totals[id] != total) {
      // 새 메시지(번호 재사용) — 이전 미완성 조각은 버린다.
      _parts[id] = {};
      _totals[id] = total;
    }
    final parts = _parts[id]!..[idx] = Uint8List.sublistView(chunk, headerLen);
    if (parts.length < total) return null;
    _parts.remove(id);
    _totals.remove(id);
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < total; i++) {
      out.add(parts[i]!);
    }
    return out.toBytes();
  }
}
