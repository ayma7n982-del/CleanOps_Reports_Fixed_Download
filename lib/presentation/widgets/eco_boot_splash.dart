import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Branded, responsive Flutter boot surface displayed after Android's native
/// launch screen. Contains only visuals: no authentication or navigation logic.
class EcoBootSplash extends StatelessWidget {
  final double progress;
  const EcoBootSplash({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 660;
    final logoSize = (width * .33).clamp(104.0, 150.0);
    final logoBoxSize = logoSize + 35;
    final fade = Curves.easeOutCubic.transform(t);
    final scale = .90 + .10 * Curves.easeOutBack.transform(t);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF8FCFA), Color(0xFFEBF8F2), Color(0xFFD9F0E6),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(painter: _BootBackdrop(progress: t)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: compact ? 12 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - (compact ? 24 : 48)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Opacity(
                        opacity: fade,
                        child: Transform.scale(
                          scale: scale,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: logoBoxSize + 48,
                                height: logoBoxSize + 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFBDE9D8),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              Container(
                                width: logoBoxSize,
                                height: logoBoxSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFDDF5E9),
                                  border: Border.all(
                                    color: const Color(0xFFC4EBD9),
                                  ),
                                ),
                              ),
                              Container(
                                height: logoSize,
                                width: logoSize,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(31),
                                  border: Border.all(
                                    color: const Color(0xFFE5F3EB),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x28348F75),
                                      blurRadius: 25,
                                      offset: Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/brand/cleanops_logo_new.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.eco_rounded,
                                    color: Color(0xFF087F6B),
                                    size: 73,
                                  ),
                                ),
                              ),
                              PositionedDirectional(
                                top: 6,
                                end: 0,
                                child: _BootBubble(
                                  icon: Icons.recycling_rounded,
                                  color: Color(0xFF088F75),
                                ),
                              ),
                              PositionedDirectional(
                                bottom: 2,
                                start: 1,
                                child: _BootBubble(
                                  icon: Icons.local_shipping_rounded,
                                  color: Color(0xFF288DA7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 27),
                      Opacity(
                        opacity: fade,
                        child: Column(
                          children: [
                            const Text(
                              'CleanOps',
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 35,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .1,
                                color: Color(0xFF104A40),
                              ),
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'منظومة ذكية لإدارة عمليات النظافة',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF154E43),
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'تنظيم أفضل • قرارات أذكى • بيئة أنظف',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF528278),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 24 : 35),
                      SizedBox(
                        width: 205,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                minHeight: 5,
                                value: t,
                                backgroundColor: const Color(0xFFC4E9D9),
                                color: const Color(0xFF0F9C7D),
                              ),
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'تهيئة مساحة العمل...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF67867E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 28),
                      const _BootCapabilities(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BootBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _BootBubble({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Color.lerp(color, Colors.white, .22)!,
            color,
          ]),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0x1E0C755F), blurRadius: 11),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 21),
      );
}

class _BootCapabilities extends StatelessWidget {
  const _BootCapabilities();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String)>[
      (Icons.hub_rounded, 'التشغيل'),
      (Icons.insights_rounded, 'التحليلات'),
      (Icons.shield_outlined, 'المتابعة'),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final entry in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.78),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFCBE9DA)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.$1, size: 15, color: const Color(0xFF178772)),
                const SizedBox(width: 5),
                Text(entry.$2, style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF27574D),
                )),
              ],
            ),
          ),
      ],
    );
  }
}

/// Subtle ecological illustration, intentionally static in geometry and cheap
/// to render while the logo fades in.
class _BootBackdrop extends CustomPainter {
  final double progress;
  const _BootBackdrop({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Paint()..color = const Color(0x3DA7DFC8);
    canvas.drawCircle(Offset(size.width * .94, size.height * .13),
        size.width * .31, circle);
    canvas.drawCircle(Offset(size.width * .04, size.height * .76),
        size.width * .37, circle);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x6653B89A);
    final center = Offset(size.width * .5, size.height * .37);
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (.26 + i * .12 + progress * .035);
      canvas.drawCircle(center, radius, line);
    }
    final small = Paint()..color = const Color(0x6677C8A8);
    for (var i = 0; i < 12; i++) {
      final radians = math.pi * 2 * i / 12;
      final p = center + Offset(
        math.cos(radians) * size.width * .46,
        math.sin(radians) * size.width * .46,
      );
      canvas.drawCircle(p, 2 + i % 3, small);
    }
  }

  @override
  bool shouldRepaint(covariant _BootBackdrop oldDelegate) =>
      oldDelegate.progress != progress;
}
