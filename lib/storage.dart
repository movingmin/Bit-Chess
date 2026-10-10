import 'dart:convert';
import 'dart:io';

import 'game.dart';

/// 앱 전용 저장소의 파일 입출력. [dir]는 앱 문서 폴더(테스트는 임시 폴더).
class Storage {
  Storage(this.dir);
  final Directory dir;

  File get _current => File('${dir.path}/current.json');
  Directory get _games => Directory('${dir.path}/games');

  /// 진행 중인 판 저장. 쓰다 꺼져도 깨지지 않게 임시 파일 → rename.
  Future<void> saveCurrent(Game g) async {
    final tmp = File('${_current.path}.tmp');
    await tmp.writeAsString(jsonEncode(g.toJson()), flush: true);
    await tmp.rename(_current.path);
  }

  Future<Game?> loadCurrent() async {
    if (!await _current.exists()) return null;
    try {
      return Game.fromJson(jsonDecode(await _current.readAsString()) as Map<String, Object?>);
    } on Object {
      return null; // 손상된 파일은 무시
    }
  }

  Future<void> clearCurrent() async {
    if (await _current.exists()) await _current.delete();
  }

  /// 끝난 판을 PGN으로 저장하고 진행 중 파일을 지운다.
  Future<File> archive(Game g) async {
    await _games.create(recursive: true);
    final f = File('${_games.path}/${g.date.millisecondsSinceEpoch}.pgn');
    await f.writeAsString(g.toPgn(), flush: true);
    await clearCurrent();
    return f;
  }

  /// 최신순.
  Future<List<File>> listGames() async {
    if (!await _games.exists()) return [];
    final files = await _games.list().where((e) => e.path.endsWith('.pgn')).cast<File>().toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}
