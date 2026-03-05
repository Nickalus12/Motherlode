import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:motherlode/motherlode_game.dart';
import 'package:motherlode/ui/genesis_screen.dart';
import 'package:motherlode/ui/hud.dart';
import 'package:motherlode/ui/main_menu.dart';
import 'package:motherlode/utils/constants.dart';
import 'package:motherlode/world/genesis_pipeline.dart';

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

enum GameScreenState { mainMenu, genesis, playing, dead }

class MotherlodeGameScreen extends ConsumerStatefulWidget {
  const MotherlodeGameScreen({super.key});

  @override
  ConsumerState<MotherlodeGameScreen> createState() =>
      _MotherlodeGameScreenState();
}

class _MotherlodeGameScreenState extends ConsumerState<MotherlodeGameScreen> {
  GameScreenState _screenState = GameScreenState.mainMenu;
  MotherlodeGame? _game;
  StreamController<(GenesisPhase, double)>? _genesisProgressController;

  /// Key to preserve the GameWidget across genesis → playing transition,
  /// avoiding a detach/re-attach cycle on the game instance.
  final _gameWidgetKey = GlobalKey();

  void _startNewGame() {
    // Create progress stream for the genesis screen
    _genesisProgressController?.close();
    _genesisProgressController =
        StreamController<(GenesisPhase, double)>.broadcast();

    setState(() {
      _screenState = GameScreenState.genesis;
    });

    // Run the genesis pipeline async, then create the game with results
    _runGenesisPipeline();
  }

  Future<void> _runGenesisPipeline() async {
    final seed = Random().nextInt(999999);

    final pipeline = GenesisPipeline(
      seed: seed,
      onProgress: (phase, progress) {
        // Bridge pipeline progress to the genesis screen stream
        _genesisProgressController?.add((phase, progress));
      },
    );

    // Run world generation (phases report progress to genesis screen)
    final result = await pipeline.generateWorld(
      chunkRadiusX: GameConstants.chunkLoadRadius,
      chunkRadiusY: GameConstants.chunkLoadRadius * 2,
    );

    if (!mounted) return;

    // Create game with pre-generated world data
    final game = MotherlodeGame(
      onGameOver: _onGameOver,
      onReady: _onGenesisReady,
      worldSeed: seed,
      genesisResult: result,
      stratigraphy: pipeline.stratigraphy,
    );
    _game = game;

    // Force a rebuild so the GameWidget picks up the new game instance
    setState(() {});
  }

  /// Called when world generation is complete. Signals the genesis screen
  /// to show "TAP TO BEGIN" state.
  void _onGenesisReady() {
    if (!mounted) return;
    _genesisProgressController?.add((GenesisPhase.worldReady, 1.0));
  }

  /// Called when the player taps through the genesis screen to start playing.
  void _onGenesisComplete() {
    if (mounted) {
      setState(() {
        _screenState = GameScreenState.playing;
      });
      _genesisProgressController?.close();
      _genesisProgressController = null;
    }
  }

  void _onGameOver() {
    setState(() {
      _screenState = GameScreenState.dead;
    });
  }

  void _returnToMenu() {
    _genesisProgressController?.close();
    _genesisProgressController = null;
    setState(() {
      _game = null;
      _screenState = GameScreenState.mainMenu;
    });
  }

  @override
  void dispose() {
    _genesisProgressController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_screenState) {
      case GameScreenState.mainMenu:
        return MainMenu(
          onNewGame: _startNewGame,
          onLoadGame: _startNewGame, // TODO: load saved game
        );

      case GameScreenState.genesis:
        return Stack(
          children: [
            // Start loading the game behind the genesis screen once
            // the pipeline has finished and created the game instance.
            if (_game != null)
              Offstage(
                child: GameWidget(
                  key: _gameWidgetKey,
                  game: _game!,
                  loadingBuilder: (_) => const SizedBox.shrink(),
                ),
              ),
            // Cinematic genesis load screen (receives progress from pipeline)
            GenesisScreen(
              onComplete: _onGenesisComplete,
              progressStream: _genesisProgressController?.stream,
            ),
          ],
        );

      case GameScreenState.playing:
        return Stack(
          children: [
            GameWidget(
              key: _gameWidgetKey,
              game: _game!,
              loadingBuilder: (_) => const SizedBox.shrink(),
            ),
            HudOverlay(game: _game!),
          ],
        );

      case GameScreenState.dead:
        return _buildDeathScreen();
    }
  }

  Widget _buildDeathScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0000),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Skull/warning icon
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Colors.red.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'DRILL DESTROYED',
              style: TextStyle(
                color: Colors.red,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                shadows: [
                  Shadow(
                    color: Colors.red.withValues(alpha: 0.5),
                    blurRadius: 20,
                  ),
                  Shadow(
                    color: Colors.red.withValues(alpha: 0.3),
                    blurRadius: 40,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 160,
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.red.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_game != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_downward,
                            color: Colors.white54, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Depth: ${_game!.depthSystem.maxDepthReached.toStringAsFixed(0)} ft',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 17),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.monetization_on,
                            color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '\$${_game!.playerCash.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.amber.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 36),
            GestureDetector(
              onTap: _startNewGame,
              child: Container(
                width: 220,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.shade900,
                      Colors.red.shade800,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'TRY AGAIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _returnToMenu,
              child: Container(
                width: 220,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Text(
                  'MAIN MENU',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

