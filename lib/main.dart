import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble/ble_debug_screen.dart';
import 'game.dart';
import 'game_screen.dart';
import 'history_screen.dart';
import 'storage.dart';

late final Storage storage;
late final SharedPreferences prefs;

bool get soundOn => prefs.getBool('sound') ?? true;
bool get vibrationOn => prefs.getBool('vibration') ?? true;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  storage = Storage(await getApplicationDocumentsDirectory());
  prefs = await SharedPreferences.getInstance();
  final resume = await storage.loadCurrent();
  runApp(BitChessApp(resume: resume));
}

class BitChessApp extends StatelessWidget {
  const BitChessApp({super.key, this.resume});
  final Game? resume;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bit-Chess',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF769656), brightness: Brightness.dark),
    ),
    home: HomeScreen(resume: resume),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.resume});
  final Game? resume;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 앱이 꺼졌다 켜지면 진행 중이던 판으로 바로 복귀.
    final g = widget.resume;
    if (g != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(g));
  }

  void _open(Game g) => Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(game: g)));

  Future<void> _newGame() async {
    final tc = await showDialog<TimeControl>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('시간 제한'),
        children: [
          for (final t in TimeControl.presets)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, t), child: Text(t.label)),
        ],
      ),
    );
    if (tc != null && mounted) _open(Game(timeControl: tc));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bit-Chess')),
    // 2단계 이후 BLE 대국(방 만들기·찾기)과 분석 보드가 이 목록에 들어온다.
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.people),
          title: const Text('혼자 두기 (Pass & Play)'),
          subtitle: const Text('한 폰에서 번갈아 두기'),
          onTap: _newGame,
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('지난 대국'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('설정'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('BLE 테스트 (디버그)'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BleDebugScreen())),
          ),
      ],
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: ListView(
      children: [
        SwitchListTile(
          title: const Text('효과음'),
          value: soundOn,
          onChanged: (v) => prefs.setBool('sound', v).then((_) => setState(() {})),
        ),
        SwitchListTile(
          title: const Text('진동'),
          value: vibrationOn,
          onChanged: (v) => prefs.setBool('vibration', v).then((_) => setState(() {})),
        ),
      ],
    ),
  );
}
