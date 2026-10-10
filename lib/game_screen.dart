import 'dart:async';
import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game.dart';
import 'main.dart';

/// Pass & Play 대국 화면. 나중에 BLE 대국도 같은 화면에 상대 입력만 바꿔 붙인다.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game});
  final Game game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  Game get g => widget.game;
  late final ChessboardController _board = ChessboardController(game: _data());
  final _turnWatch = Stopwatch(); // 단조 시계: 이번 차례에 쓴 시간
  Timer? _ticker;
  Side _orientation = Side.white;

  bool get _timed => g.timeControl.initialMs != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!g.isOver) _startClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _board.dispose();
    super.dispose();
  }

  // 앱이 백그라운드로 가면(강제 중지 직전 포함) 쓴 시간까지 반영해 저장.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (g.isOver) return;
    if (s == AppLifecycleState.paused) {
      _commitElapsed();
      _turnWatch.stop();
      storage.saveCurrent(g);
    } else if (s == AppLifecycleState.resumed) {
      _turnWatch.start();
    }
  }

  void _startClock() {
    _turnWatch
      ..reset()
      ..start();
    if (_timed) {
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_remaining(g.pos.turn) <= 0) {
          g.flag(g.pos.turn);
          _finish();
        }
        setState(() {});
      });
    }
  }

  void _commitElapsed() {
    if (_timed) g.clockMs[g.pos.turn == Side.white ? 0 : 1] -= _turnWatch.elapsedMilliseconds;
    _turnWatch.reset();
  }

  int _remaining(Side s) {
    final base = g.clockMs[s == Side.white ? 0 : 1];
    return s == g.pos.turn && !g.isOver ? base - _turnWatch.elapsedMilliseconds : base;
  }

  GameData _data() => GameData(
        fen: g.pos.fen,
        lastMove: g.lastMove,
        playerSide: g.isOver
            ? PlayerSide.none
            : (g.pos.turn == Side.white ? PlayerSide.white : PlayerSide.black),
        sideToMove: g.pos.turn,
        validMoves: makeLegalMoves(g.pos),
        kingSquareInCheck: g.pos.isCheck ? g.pos.board.kingOf(g.pos.turn) : null,
      );

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final capture = move is NormalMove && g.pos.board.pieceAt(move.to) != null;
    final san = g.play(move, spentMs: _turnWatch.elapsedMilliseconds);
    if (san == null) return;
    _turnWatch.reset();
    _board.updatePosition(_data());
    _feedback(strong: capture || g.pos.isCheck || g.isOver);
    if (g.isOver) {
      _finish();
    } else {
      storage.saveCurrent(g);
    }
    setState(() {});
  }

  // ponytail: 시스템 클릭음 하나로 이동·잡기·체크·종료를 낸다. 구분음은 라이선스 확인된 음원을 넣을 때.
  void _feedback({bool strong = false}) {
    if (soundOn) SystemSound.play(SystemSoundType.click);
    if (vibrationOn) strong ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _turnWatch.stop();
    _board.updatePosition(_data());
    _feedback(strong: true);
    await storage.archive(g);
    if (!mounted) return;
    setState(() {});
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_resultText),
        content: Text(g.reason ?? ''),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))],
      ),
    );
  }

  String get _resultText => switch (g.result) {
        '1-0' => '백 승 (1-0)',
        '0-1' => '흑 승 (0-1)',
        '1/2-1/2' => '무승부 (½-½)',
        _ => '진행 중',
      };

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('아니요')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('예')),
          ],
        ),
      ) ??
      false;

  Future<void> _resign() async {
    final side = g.pos.turn;
    if (await _confirm('${side == Side.white ? '백' : '흑'}이 기권할까요?') && !g.isOver) {
      g.resign(side);
      _finish();
    }
  }

  Future<void> _draw() async {
    final other = g.pos.turn == Side.white ? '흑' : '백';
    if (await _confirm('무승부 제안 — $other도 동의하나요?') && !g.isOver) {
      g.agreeDraw();
      _finish();
    }
  }

  /// 진행 중에 나가면 '중단'으로 기보를 남긴다.
  Future<void> _leave() async {
    if (!g.isOver) {
      if (!await _confirm('대국을 중단하고 나갈까요? 기보는 저장됩니다.')) return;
      _ticker?.cancel();
      g.reason = '중단';
      await storage.archive(g);
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _clock(Side s) {
    final ms = max(0, _remaining(s));
    final active = !g.isOver && g.pos.turn == s;
    final text = _timed
        ? '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}${ms < 10000 ? '.${ms ~/ 100 % 10}' : ''}'
        : '∞';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(s == Side.white ? g.white : g.black, style: const TextStyle(fontSize: 18)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: active ? Colors.white : Colors.black26,
            child: Text(text,
                style: TextStyle(fontSize: 22, fontFamily: 'monospace', color: active ? Colors.black : Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _moves() {
    final s = StringBuffer();
    for (var i = 0; i < g.sans.length; i++) {
      if (i.isEven) s.write('${i ~/ 2 + 1}. ');
      s.write('${g.sans[i]} ');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      padding: const EdgeInsets.all(8),
      child: Text(s.isEmpty ? '-' : s.toString()),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => didPop ? null : _leave(),
        child: Scaffold(
          appBar: AppBar(title: Text(g.isOver ? _resultText : 'Pass & Play')),
          body: LayoutBuilder(
            builder: (context, c) => Column(
              children: [
                _moves(),
                _clock(_orientation.opposite),
                Chessboard(
                  controller: _board,
                  size: min(c.maxWidth, c.maxHeight - 220),
                  orientation: _orientation,
                  onMove: _onMove,
                ),
                _clock(_orientation),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.swap_vert),
                      label: const Text('뒤집기'),
                      onPressed: () => setState(() => _orientation = _orientation.opposite),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.handshake),
                      label: const Text('무승부'),
                      onPressed: g.isOver ? null : _draw,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.flag),
                      label: const Text('기권'),
                      onPressed: g.isOver ? null : _resign,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
}
