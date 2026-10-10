import 'dart:io';

import 'package:bit_chess/game.dart';
import 'package:bit_chess/storage.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

Game playAll(String moves, {TimeControl tc = const TimeControl('무제한', null)}) {
  final g = Game(timeControl: tc, date: DateTime(2026, 10, 9));
  for (final s in moves.split(' ').where((s) => s.isNotEmpty && !s.endsWith('.'))) {
    final m = g.pos.parseSan(s);
    expect(m, isNotNull, reason: s);
    expect(g.play(m!), isNotNull, reason: s);
  }
  return g;
}

void main() {
  test('바보의 메이트', () {
    final g = playAll('f3 e5 g4 Qh4#');
    expect(g.result, '0-1');
    expect(g.reason, '체크메이트');
    expect(g.sans.last, 'Qh4#');
  });

  test('스테일메이트', () {
    final g = playAll('e3 a5 Qh5 Ra6 Qxa5 h5 h4 Rah6 Qxc7 f6 Qxd7+ Kf7 Qxb7 Qd3 Qxb8 Qh7 Qxc8 Kg6 Qe6');
    expect(g.result, '1/2-1/2');
    expect(g.reason, '스테일메이트');
  });

  test('3회 반복', () {
    final g = playAll('Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8');
    expect(g.reason, '3회 반복');
  });

  test('기물 부족', () {
    final g = Game(timeControl: TimeControl.presets.first);
    g.pos = Chess.fromSetup(Setup.parseFen('8/8/8/4k3/8/8/3q4/4K3 w - - 0 1'));
    g.play(g.pos.parseSan('Kxd2')!);
    expect(g.reason, '기물 부족');
  });

  test('핀 걸린 말은 못 움직이고, 끝난 판엔 수를 못 둔다', () {
    final p = Game(timeControl: TimeControl.presets.first);
    p.pos = Chess.fromSetup(Setup.parseFen('4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1'));
    expect(p.play(NormalMove(from: Square.e2, to: Square.c3)), isNull);
    final over = playAll('f3 e5 g4 Qh4#');
    expect(over.play(NormalMove(from: Square.e2, to: Square.e4)), isNull);
    expect(over.isOver, isTrue);
  });

  test('보드가 보내는 킹 2칸 캐슬링(e1→g1, e8→c8)', () {
    final g = playAll('e4 d5 Nf3 Qd6 Bc4 Be6 d3 Nc6');
    expect(g.play(NormalMove(from: Square.e1, to: Square.g1)), 'O-O');
    expect(g.pos.board.roleAt(Square.f1), Role.rook);
    expect(g.play(NormalMove(from: Square.e8, to: Square.c8)), 'O-O-O');
    expect(g.pos.board.roleAt(Square.d8), Role.rook);
  });

  test('특수 수 PGN: 앙파상·캐슬링·프로모션', () {
    final ep = playAll('e4 a6 e5 d5 exd6');
    expect(ep.pos.board.pieceAt(Square.d5), isNull);
    final castle = playAll('e4 e5 Nf3 Nc6 Bc4 Bc5 O-O d6 d3 Be6 Nc3 Qd7 Be3 O-O-O');
    final promo = playAll('h4 g5 hxg5 h6 gxh6 Nf6 h7 Rg8 hxg8=N');
    for (final g in [ep, castle, promo]) {
      final pgn = g.toPgn();
      final back = PgnGame.parsePgn(pgn).moves.mainline().map((n) => n.san).toList();
      expect(back, g.sans);
    }
    expect(castle.toPgn(), contains('O-O-O'));
    expect(promo.toPgn(), contains('hxg8=N'));
    expect(ep.toPgn(), contains('[TimeControl "-"]'));
  });

  test('기권·시간패·증초', () {
    final g = playAll('e4', tc: TimeControl.presets.last); // 15+10
    expect(g.clockMs[0], 910000);
    g.play(g.pos.parseSan('e5')!, spentMs: 5000);
    expect(g.clockMs[1], 905000);
    g.flag(Side.white);
    expect(g.result, '0-1');
    final r = playAll('e4');
    r.resign(Side.black);
    expect(r.result, '1-0');
  });

  test('저장·복구', () async {
    final dir = await Directory.systemTemp.createTemp('bitchess');
    final s = Storage(dir);
    final g = playAll('e4 c5 Nf3 d6', tc: TimeControl.presets[2]);
    g.clockMs[0] = 123456;
    await s.saveCurrent(g);
    final r = (await s.loadCurrent())!;
    expect(r.sans, g.sans);
    expect(r.pos.fen, g.pos.fen);
    expect(r.pos.turn, Side.white);
    expect(r.clockMs, g.clockMs);
    expect(r.timeControl.pgn, '300+0');

    await s.archive(g);
    expect(await s.loadCurrent(), isNull);
    final files = await s.listGames();
    expect(files, hasLength(1));
    expect(files.first.readAsStringSync(), contains('1. e4 c5 2. Nf3 d6'));
    await dir.delete(recursive: true);
  });
}
