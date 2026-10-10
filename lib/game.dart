import 'package:dartchess/dartchess.dart';

/// 시간 제한. initialMs == null 이면 무제한.
class TimeControl {
  const TimeControl(this.label, this.initialMs, [this.incrementMs = 0]);
  final String label;
  final int? initialMs;
  final int incrementMs;

  /// PGN TimeControl 헤더 값.
  String get pgn => initialMs == null ? '-' : '${initialMs! ~/ 1000}+${incrementMs ~/ 1000}';

  static const presets = [
    TimeControl('무제한', null),
    TimeControl('3분', 180000),
    TimeControl('5분', 300000),
    TimeControl('10분', 600000),
    TimeControl('15+10', 900000, 10000),
  ];

  static TimeControl fromPgn(String s) => presets.firstWhere(
    (t) => t.pgn == s,
    orElse: () {
      final p = s.split('+');
      return p.length == 2 ? TimeControl(s, int.parse(p[0]) * 1000, int.parse(p[1]) * 1000) : presets.first;
    },
  );
}

/// 한 판의 상태. UI·저장과 무관한 순수 로직(테스트 대상).
class Game {
  Game({required this.timeControl, this.white = '백', this.black = '흑', DateTime? date})
    : date = date ?? DateTime.now(),
      clockMs = [timeControl.initialMs ?? 0, timeControl.initialMs ?? 0];

  final TimeControl timeControl;
  final String white, black;
  final DateTime date;

  Position pos = Chess.initial;
  final List<String> sans = [];
  Move? lastMove;

  /// 각 쪽이 잡은 상대 기물(잡은 순서). 복구 때는 수를 다시 두며 다시 쌓인다.
  final Map<Side, List<Role>> captured = {Side.white: [], Side.black: []};

  /// [백, 흑] 남은 시간(ms).
  final List<int> clockMs;

  /// '*', '1-0', '0-1', '1/2-1/2'
  String result = '*';

  /// 끝난 이유(한국어). 진행 중이면 null.
  String? reason;

  final Map<String, int> _seen = {_repKey(Chess.initial): 1};

  bool get isOver => result != '*';

  static String _repKey(Position p) => p.fen.split(' ').take(4).join(' ');
  static int _idx(Side s) => s == Side.white ? 0 : 1;

  /// 수를 둔다. 둔 쪽이 이번 차례에 쓴 시간 [spentMs]를 빼고 증초를 더한다.
  /// 불법 수면 null, 아니면 SAN을 돌려준다.
  String? play(Move move, {int spentMs = 0}) {
    if (isOver || !pos.isLegal(move)) return null;
    final mover = pos.turn;
    if (timeControl.initialMs != null) {
      clockMs[_idx(mover)] += timeControl.incrementMs - spentMs;
    }
    final (next, san) = pos.makeSan(move);
    // 상대 기물 중 줄어든 종류 = 잡힌 기물(앙파상 포함, 프로모션은 내 기물이라 무관).
    for (final r in Role.values) {
      if (next.board.piecesOf(mover.opposite, r).size < pos.board.piecesOf(mover.opposite, r).size) {
        captured[mover]!.add(r);
      }
    }
    pos = next;
    sans.add(san);
    lastMove = move;
    final key = _repKey(pos);
    _seen[key] = (_seen[key] ?? 0) + 1;

    if (pos.isCheckmate) {
      _end(mover == Side.white ? '1-0' : '0-1', '체크메이트');
    } else if (pos.isStalemate) {
      _end('1/2-1/2', '스테일메이트');
    } else if (pos.isInsufficientMaterial) {
      _end('1/2-1/2', '기물 부족');
    } else if (_seen[key]! >= 3) {
      _end('1/2-1/2', '3회 반복');
    } else if (pos.halfmoves >= 100) {
      _end('1/2-1/2', '50수 규칙');
    }
    return san;
  }

  void resign(Side loser) => _end(loser == Side.white ? '0-1' : '1-0', '${loser == Side.white ? '백' : '흑'} 기권');

  void agreeDraw() => _end('1/2-1/2', '합의 무승부');

  /// 시간패. 상대가 메이트시킬 기물이 없으면 무승부(FIDE 6.9).
  void flag(Side loser) {
    clockMs[_idx(loser)] = 0;
    if (pos.hasInsufficientMaterial(loser.opposite)) {
      _end('1/2-1/2', '시간 초과·기물 부족');
    } else {
      _end(loser == Side.white ? '0-1' : '1-0', '시간패');
    }
  }

  void _end(String r, String why) {
    if (isOver) return;
    result = r;
    reason = why;
  }

  String get _date => '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  String toPgn() {
    final root = PgnNode<PgnNodeData>();
    PgnNode<PgnNodeData> cur = root;
    for (final s in sans) {
      final child = PgnChildNode(PgnNodeData(san: s));
      cur.children.add(child);
      cur = child;
    }
    return PgnGame(
      headers: {
        'Event': 'Bit-Chess Pass & Play',
        'Site': 'Bit-Chess',
        'Date': _date,
        'Round': '-',
        'White': white,
        'Black': black,
        'Result': result,
        'TimeControl': timeControl.pgn,
        'Termination': ?reason,
      },
      moves: root,
      comments: const [],
    ).makePgn();
  }

  /// 진행 중 판 복구용.
  Map<String, Object?> toJson() => {
    'tc': timeControl.pgn,
    'white': white,
    'black': black,
    'date': date.toIso8601String(),
    'sans': sans,
    'clock': clockMs,
    'result': result,
    'reason': reason,
  };

  static Game fromJson(Map<String, Object?> j) {
    final g = Game(
      timeControl: TimeControl.fromPgn(j['tc'] as String),
      white: j['white'] as String,
      black: j['black'] as String,
      date: DateTime.parse(j['date'] as String),
    );
    for (final s in (j['sans'] as List).cast<String>()) {
      final m = g.pos.parseSan(s);
      if (m == null || g.play(m) == null) throw FormatException('잘못된 수: $s');
    }
    final c = (j['clock'] as List).cast<int>();
    g.clockMs
      ..[0] = c[0]
      ..[1] = c[1];
    g.result = j['result'] as String;
    g.reason = j['reason'] as String?;
    return g;
  }
}

/// 기물 점수(폰1·나이트3·비숍3·룩5·퀸9).
const pieceValue = {Role.pawn: 1, Role.knight: 3, Role.bishop: 3, Role.rook: 5, Role.queen: 9, Role.king: 0};

/// 낮은 점수부터 정렬.
List<Role> sortedByValue(List<Role> roles) => [...roles]..sort((a, b) => pieceValue[a]!.compareTo(pieceValue[b]!));

/// 백 기준 점수 차(백이 앞서면 +).
int materialDiff(Position pos) {
  int sum(Side s) => Role.values.fold(0, (a, r) => a + pos.board.piecesOf(s, r).size * pieceValue[r]!);
  return sum(Side.white) - sum(Side.black);
}
