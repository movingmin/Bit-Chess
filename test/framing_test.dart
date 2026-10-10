import 'dart:math';
import 'dart:typed_data';

import 'package:bit_chess/ble/framing.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int n) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) & 0xFF));

void main() {
  test('경계 크기: 0, 1, 조각 하나 꽉, 하나 넘김, 2KB, 큰 MTU', () {
    for (final chunk in [20, 182, 512]) {
      final body = chunk - headerLen;
      for (final n in [0, 1, body - 1, body, body + 1, 2048, 5000]) {
        final msg = bytes(n);
        final parts = split(msg, 3, chunk);
        expect(parts.every((p) => p.length <= chunk), isTrue);
        expect(parts.length, n == 0 ? 1 : (n + body - 1) ~/ body, reason: 'n=$n chunk=$chunk');
        final r = Reassembler();
        Uint8List? out;
        for (final p in parts) {
          out = r.add(p);
        }
        expect(out, msg, reason: 'n=$n chunk=$chunk');
      }
    }
  });

  test('순서 뒤섞임·중복 조각', () {
    final msg = bytes(2048);
    final parts = split(msg, 9, 20)..shuffle(Random(1));
    final r = Reassembler();
    final outs = [
      for (final p in [...parts, parts.first]) r.add(p),
    ].whereType<Uint8List>().toList();
    expect(outs, [msg]);
  });

  test('조각 누락이면 완성되지 않고, 다른 메시지는 영향 없음', () {
    final r = Reassembler();
    final a = split(bytes(100), 1, 20)..removeAt(2);
    for (final p in a) {
      expect(r.add(p), isNull);
    }
    final b = bytes(50);
    Uint8List? out;
    for (final p in split(b, 2, 20)) {
      out = r.add(p);
    }
    expect(out, b);
  });

  test('번호가 같은 새 메시지는 이전 미완성 조각을 버림', () {
    final r = Reassembler();
    r.add(split(bytes(100), 5, 20).first); // 미완성
    final b = bytes(30);
    Uint8List? out;
    for (final p in split(b, 5, 20)) {
      out = r.add(p);
    }
    expect(out, b);
  });

  test('깨진 조각 무시', () {
    final r = Reassembler();
    expect(r.add(Uint8List(3)), isNull);
    expect(r.add(Uint8List.fromList([1, 0, 5, 0, 2, 9])), isNull); // idx >= total
    expect(r.add(Uint8List.fromList([1, 0, 0, 0, 0])), isNull); // total 0
  });
}
