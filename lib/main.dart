import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/ui/hud.dart';
import 'package:motherlode/ui/main_menu.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Full screen immersive mode
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialize Hive for persistence
  await Hive.initFlutter();

  runApp(
    const ProviderScope(
      child: MotherlodeApp(),
    ),
  );
}

class MotherlodeApp extends StatelessWidget {
  const MotherlodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motherlode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MotherlodeGameScreen(),
    );
  }
}

enum GameScreenState { mainMenu, playing, dead }

class MotherlodeGameScreen extends ConsumerStatefulWidget {
  const MotherlodeGameScreen({super.key});

  @override
  ConsumerState<MotherlodeGameScreen> createState() => _MotherlodeGameScreenState();
}

class _MotherlodeGameScreenState extends ConsumerState<MotherlodeGameScreen> {
  GameScreenState _screenState = GameScreenState.mainMenu;
  MotherlodeGame? _game;

  void _startNewGame() {
    setState(() {
      _game = MotherlodeGame(
        onGameOver: _onGameOver,
      );
      _screenState = GameScreenState.playing;
    });
  }

  void _onGameOver() {
    setState(() {
      _screenState = GameScreenState.dead;
    });
  }

  void _returnToMenu() {
    setState(() {
      _game = null;
      _screenState = GameScreenState.mainMenu;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_screenState) {
      case GameScreenState.mainMenu:
        return MainMenu(
          onNewGame: _startNewGame,
          onLoadGame: _startNewGame, // TODO: load saved game
        );

      case GameScreenState.playing:
        return Stack(
          children: [
            GameWidget(game: _game!),
            HudOverlay(game: _game!),
          ],
        );

      case GameScreenState.dead:
        return _buildDeathScreen();
    }
  }

  Widget _buildDeathScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'DRILL DESTROYED',
              style: TextStyle(
                color: Colors.red,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            if (_game != null) ...[
              Text(
                'Depth Reached: ${_game!.depthSystem.maxDepthReached.toStringAsFixed(0)} ft',
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Cash Earned: \$${_game!.playerCash.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.amber, fontSize: 18),
              ),
            ],
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _startNewGame,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: const Text('TRY AGAIN', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _returnToMenu,
              child: const Text('MAIN MENU',
                  style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }
}
