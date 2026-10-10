import 'dart:io';
import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'main.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('지난 대국')),
        body: FutureBuilder<List<File>>(
          future: storage.listGames(),
          builder: (context, snap) {
            final files = snap.data;
            if (files == null) return const Center(child: CircularProgressIndicator());
            if (files.isEmpty) return const Center(child: Text('저장된 대국이 없습니다'));
            return ListView(
              children: [
                for (final f in files)
                  Builder(builder: (context) {
                    final pgn = f.readAsStringSync();
                    final h = PgnGame.parsePgn(pgn).headers;
                    return ListTile(
                      title: Text('${h['White']} vs ${h['Black']}  ${h['Result']}'),
                      subtitle: Text('${h['Date']} · ${h['TimeControl']} · ${h['Termination'] ?? ''}'),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => ReplayScreen(file: f, pgn: pgn))),
                    );
                  }),
              ],
            );
          },
        ),
      );
}

class ReplayScreen extends StatefulWidget {
  const ReplayScreen({super.key, required this.file, required this.pgn});
  final File file;
  final String pgn;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  /// positions[i] = i수 둔 뒤 국면, moves[i-1] = i번째 수.
  final positions = <Position>[Chess.initial];
  final moves = <Move>[];
  final sans = <String>[];
  int ply = 0;

  @override
  void initState() {
    super.initState();
    for (final node in PgnGame.parsePgn(widget.pgn).moves.mainline()) {
      final m = positions.last.parseSan(node.san);
      if (m == null) break;
      moves.add(m);
      sans.add(node.san);
      positions.add(positions.last.play(m));
    }
    ply = moves.length;
  }

  void _go(int p) => setState(() => ply = p.clamp(0, moves.length));

  @override
  Widget build(BuildContext context) {
    final pos = positions[ply];
    return Scaffold(
      appBar: AppBar(
        title: const Text('다시보기'),
        actions: [
          IconButton(
            tooltip: '내보내기',
            icon: const Icon(Icons.share),
            onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(widget.file.path)])),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(ply == 0 ? '시작 위치' : '${(ply + 1) ~/ 2}${ply.isOdd ? '.' : '...'} ${sans[ply - 1]}'),
            ),
            StaticChessboard(
              size: min(c.maxWidth, c.maxHeight - 140),
              orientation: Side.white,
              fen: pos.fen,
              lastMove: ply == 0 ? null : moves[ply - 1],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.first_page), onPressed: () => _go(0)),
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _go(ply - 1)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _go(ply + 1)),
                IconButton(icon: const Icon(Icons.last_page), onPressed: () => _go(moves.length)),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
