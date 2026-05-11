import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-screen celebration overlay shown when the user finishes a book.
/// Displays a scale-in animation with particle effects, book title,
/// and congratulatory message.
class BookCompletionOverlay extends StatefulWidget {
  final String bookTitle;
  final String? readingTimeLabel;
  final String? paceLabel;
  final VoidCallback onDismiss;
  final VoidCallback onGoToLibrary;

  const BookCompletionOverlay({
    super.key,
    required this.bookTitle,
    this.readingTimeLabel,
    this.paceLabel,
    required this.onDismiss,
    required this.onGoToLibrary,
  });

  @override
  State<BookCompletionOverlay> createState() => _BookCompletionOverlayState();
}

class _BookCompletionOverlayState extends State<BookCompletionOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _particleController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _textFadeAnim;
  late final List<_Particle> _particles;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();

    // Main content animation
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.3,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_mainController);

    _fadeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    );

    _textFadeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      ),
    );

    // Particle animation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Generate celebration particles
    _particles = List.generate(40, (_) => _Particle.random(_random));

    _mainController.forward();
    _particleController.forward();

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss([VoidCallback? action]) {
    _mainController.reverse().then((_) {
      if (mounted) {
        if (action != null) {
          action();
        } else {
          widget.onDismiss();
        }
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_mainController, _particleController]),
      builder: (context, _) {
        return Container(
          color: Colors.black.withValues(alpha: 0.85 * _fadeAnim.value),
          child: Stack(
            children: [
              // Particles
              ..._buildParticles(context),

              // Main content
              Center(
                child: Transform.scale(
                  scale: _scaleAnim.value,
                  child: Opacity(
                    opacity: _fadeAnim.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Celebration emoji
                        const Text('🎉', style: TextStyle(fontSize: 72)),
                        const SizedBox(height: 24),

                        // Congratulatory text
                        Opacity(
                          opacity: _textFadeAnim.value,
                          child: Column(
                            children: [
                              Text(
                                'You finished',
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                ),
                                child: Text(
                                  widget.bookTitle,
                                  style: GoogleFonts.literata(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFE85D04,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFE85D04,
                                    ).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  '📖  100% Complete',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFFF8C38),
                                  ),
                                ),
                              ),
                              if (widget.readingTimeLabel != null ||
                                  widget.paceLabel != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  [
                                    if (widget.readingTimeLabel != null)
                                      widget.readingTimeLabel!,
                                    if (widget.paceLabel != null)
                                      widget.paceLabel!,
                                  ].join('  •  '),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.78),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 32),
                              // ── Action Buttons ──
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  OutlinedButton(
                                    onPressed: _dismiss,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    child: Text(
                                      'Close',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _dismiss(widget.onGoToLibrary),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE85D04),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                    child: Text(
                                      'Go to Library',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildParticles(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final t = _particleController.value;

    return _particles.map((p) {
      final x =
          screenSize.width * p.startX +
          p.velocityX * t * screenSize.width * 0.3;
      final y =
          screenSize.height * p.startY +
          p.velocityY * t * screenSize.height * 0.4 -
          (p.gravity * t * t * screenSize.height * 0.3);

      final opacity = (1.0 - t).clamp(0.0, 1.0) * p.opacity;
      final size = p.size * (1 + t * 0.5);

      return Positioned(
        left: x,
        top: y,
        child: Transform.rotate(
          angle: p.rotation + t * p.rotationSpeed,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: p.color,
                borderRadius: p.isCircle
                    ? BorderRadius.circular(size / 2)
                    : BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

/// A single celebration particle.
class _Particle {
  final double startX;
  final double startY;
  final double velocityX;
  final double velocityY;
  final double gravity;
  final double size;
  final double opacity;
  final double rotation;
  final double rotationSpeed;
  final Color color;
  final bool isCircle;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.velocityX,
    required this.velocityY,
    required this.gravity,
    required this.size,
    required this.opacity,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
    required this.isCircle,
  });

  static const _colors = [
    Color(0xFFE85D04),
    Color(0xFFFF8C38),
    Color(0xFFFFD54F),
    Color(0xFF4CAF50),
    Color(0xFF64B5F6),
    Color(0xFFCE93D8),
    Color(0xFFEF5350),
    Color(0xFFFFFFFF),
  ];

  factory _Particle.random(math.Random r) {
    return _Particle(
      startX: 0.3 + r.nextDouble() * 0.4, // cluster around center
      startY: 0.3 + r.nextDouble() * 0.2,
      velocityX: (r.nextDouble() - 0.5) * 2.0,
      velocityY: (r.nextDouble() - 0.5) * 2.0,
      gravity: r.nextDouble() * 0.5 + 0.2,
      size: r.nextDouble() * 8 + 4,
      opacity: r.nextDouble() * 0.5 + 0.5,
      rotation: r.nextDouble() * math.pi * 2,
      rotationSpeed: (r.nextDouble() - 0.5) * math.pi * 4,
      color: _colors[r.nextInt(_colors.length)],
      isCircle: r.nextBool(),
    );
  }
}
