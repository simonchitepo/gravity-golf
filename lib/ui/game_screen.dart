import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/music_service.dart';
import '../game/game_controller.dart';
import '../game/game_painter.dart';
import '../audio/audio_settings.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController _controller;
  final FocusNode _focusNode = FocusNode();

  bool _musicMuted = false;
  bool _audioReady = false;

  @override
  void initState() {
    super.initState();
    _controller = GameController()..init();
    _initAudio();
  }

  Future<void> _initAudio() async {
    _musicMuted = await AudioSettings.loadMuted();
    await MusicService().init(muted: _musicMuted);
    if (!mounted) return;
    setState(() => _audioReady = true);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _setMusicMuted(bool muted) async {
    setState(() => _musicMuted = muted);
    await AudioSettings.saveMuted(muted);
    await MusicService().setMuted(muted);
  }

  void _openMenu() {
    showDialog(
      context: context,
      builder: (_) => _MenuDialog(
        controller: _controller,
        musicMuted: _musicMuted,
        onToggleMusic: (muted) => _setMusicMuted(muted),
      ),
    );
  }

  bool get _isMobile {
    if (kIsWeb) return false; // keep desktop-ish controls on web
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (e) {
        if (e is! RawKeyDownEvent) return;
        final key = e.logicalKey;

        if (key == LogicalKeyboardKey.space) {
          _controller.onFlip();
        } else if (key == LogicalKeyboardKey.keyP) {
          _controller.togglePause();
        } else if (key == LogicalKeyboardKey.keyR) {
          _controller.restartLevel();
        } else if (key == LogicalKeyboardKey.escape) {
          _openMenu();
        }
      },
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            return Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _controller.onFlip,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _controller.setViewport(
                        Size(constraints.maxWidth, constraints.maxHeight),
                        MediaQuery.of(context).devicePixelRatio,
                      );
                      return CustomPaint(
                        painter: GamePainter(_controller),
                        size: Size.infinite,
                        isComplex: true,
                        willChange: true,
                      );
                    },
                  ),
                ),

                // HUD
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 10,
                  right: 10,
                  child: IgnorePointer(
                    ignoring: false,
                    child: _Hud(
                      controller: _controller,
                      audioReady: _audioReady,
                      onMenu: _openMenu,
                      isMobile: _isMobile,
                    ),
                  ),
                ),

                // Start overlay
                if (_controller.showStartOverlay)
                  _OverlayCard(
                    title: '100 random levels. One tap.',
                    body:
                    'Tap (or Space) to flip gravity. Reach the hole to win.\n'
                        'Your ball never stops drifting left/right, so route using bounces and timing.\n\n'
                        'Optional: collect ★ along the way.',
                    primaryText: 'Play',
                    onPrimary: _controller.startGame,
                    secondaryText: null,
                    onSecondary: null,
                  ),

                // Message overlay (win/lose)
                if (_controller.messageOverlay != null)
                  _OverlayCard(
                    title: _controller.messageOverlay!.title,
                    body: _controller.messageOverlay!.body,
                    hint: _controller.messageOverlay!.hint,
                    primaryText: _controller.messageOverlay!.showNext ? 'Next' : null,
                    onPrimary:
                    _controller.messageOverlay!.showNext ? _controller.nextLevel : null,
                    secondaryText: 'Restart',
                    onSecondary: _controller.restartLevel,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  final GameController controller;
  final bool audioReady;
  final VoidCallback onMenu;
  final bool isMobile;

  const _Hud({
    required this.controller,
    required this.audioReady,
    required this.onMenu,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // MOBILE: minimal HUD + settings icon
    if (isMobile) {
      return Row(
        children: [
          // (optional) left spacer / nothing
          const SizedBox(width: 4),

          Expanded(
            child: Align(
              alignment: Alignment.center,
              /*child: _Pill(
                children: [
                  Text(
                    'Level: ${controller.levelNo}/100',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const Opacity(opacity: 0.5, child: Text(' • ')),
                  Text(
                    'Flips: ${controller.flips}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),*/
            ),
          ),

          // Right-side compact controls
          _IconPillButton(
            tooltip: 'Settings',
            icon: Icons.settings,
            onPressed: onMenu,
          ),
          const SizedBox(width: 8),
          _IconPillButton(
            tooltip: 'Restart',
            icon: Icons.refresh,
            onPressed: controller.restartLevel,
          ),
          const SizedBox(width: 8),
          _IconPillButton(
            tooltip: controller.paused ? 'Resume' : 'Pause',
            icon: controller.paused ? Icons.play_arrow : Icons.pause,
            onPressed: controller.togglePause,
            filled: true,
            fillColor: cs.primary,
            iconColor: cs.onPrimary,
          ),
        ],
      );
    }

    // DESKTOP/WEB: keep your full buttons + keyboard hints
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 10,
      spacing: 10,
      children: [
        _Pill(
          children: const [
            SizedBox(width: 6),
            _Kbd('Tap / Space'),
            _Kbd('P Pause'),
            _Kbd('R Restart'),
            _Kbd('Esc Menu'),
          ],
        ),
        _Pill(
          children: [
            Text(
              'Level: ${controller.levelNo}/100',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const Opacity(opacity: 0.5, child: Text(' • ')),
            Text(
              'Flips: ${controller.flips}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonal(
              onPressed: onMenu,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu, size: 18),
                  const SizedBox(width: 8),
                  Text(audioReady ? 'Menu' : 'Menu…'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: controller.restartLevel,
              child: const Text('Restart'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: controller.togglePause,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              child: Text(controller.paused ? 'Resume' : 'Pause'),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconPillButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool filled;
  final Color? fillColor;
  final Color? iconColor;

  const _IconPillButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.filled = false,
    this.fillColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? (fillColor ?? Theme.of(context).colorScheme.primary)
        : Colors.white.withOpacity(0.85);
    final fg = filled
        ? (iconColor ?? Theme.of(context).colorScheme.onPrimary)
        : const Color(0xFF0E1A24).withOpacity(0.80);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.70)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                  color: const Color(0xFF0A1928).withOpacity(0.10),
                )
              ],
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

class _MenuDialog extends StatelessWidget {
  final GameController controller;
  final bool musicMuted;
  final ValueChanged<bool> onToggleMusic;

  const _MenuDialog({
    required this.controller,
    required this.musicMuted,
    required this.onToggleMusic,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Gravity Golf — Menu',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // MUSIC TOGGLE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(musicMuted ? Icons.volume_off : Icons.music_note),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Background music',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Switch(
                      value: !musicMuted,
                      onChanged: (on) => onToggleMusic(!on),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              const Text('How to play', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                '• Tap / Space: flip gravity\n'
                    '• Reach the hole (flag) to win\n'
                    '• The ball constantly drifts left/right\n'
                    '• Use bounces + timing to route through gaps\n'
                    '• Avoid hazards (spikes/lasers/red blocks)\n'
                    '• Optional: collect ★ coins',
                style: TextStyle(height: 1.35, color: Colors.black.withOpacity(0.78)),
              ),

              const SizedBox(height: 14),

              const Text('Controls', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _Kbd('Tap / Space'),
                  _Kbd('P Pause'),
                  _Kbd('R Restart'),
                  _Kbd('Esc Menu'),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      controller.restartLevel();
                    },
                    child: const Text('Restart'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                    child: Text(controller.paused ? 'Resume' : 'Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayCard extends StatelessWidget {
  final String title;
  final String body;
  final String? hint;
  final String? primaryText;
  final VoidCallback? onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  const _OverlayCard({
    required this.title,
    required this.body,
    this.hint,
    required this.primaryText,
    required this.onPrimary,
    required this.secondaryText,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.12),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            elevation: 12,
            color: Colors.white.withOpacity(0.92),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: TextStyle(
                      height: 1.45,
                      color: Colors.black.withOpacity(0.82),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hint ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withOpacity(0.60),
                          ),
                        ),
                      ),
                      if (secondaryText != null)
                        TextButton(onPressed: onSecondary, child: Text(secondaryText!)),
                      if (primaryText != null) const SizedBox(width: 8),
                      if (primaryText != null)
                        FilledButton(
                          onPressed: onPrimary,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                          ),
                          child: Text(primaryText!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final List<Widget> children;
  const _Pill({required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.70)),
        boxShadow: [
          BoxShadow(
            blurRadius: 28,
            offset: const Offset(0, 10),
            color: const Color(0xFF0A1928).withOpacity(0.10),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: children,
        ),
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  final String text;
  const _Kbd(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A24).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0E1A24).withOpacity(0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}