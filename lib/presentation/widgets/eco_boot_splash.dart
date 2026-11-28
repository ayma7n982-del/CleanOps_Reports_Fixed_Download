import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Branded, responsive Flutter boot surface displayed after Android's native
/// launch screen. Contains only visuals: no authentication or navigation logic.
class EcoBootSplash extends StatelessWidget {
  const EcoBootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 660;
    final logoSize = (width * .33).clamp(104.0, 150.0);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8FCFA), Color(0xFFEBF8F2), Color(0xFFD9F0E6)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _BootBackdrop())),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: compact ? 12 : 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(
                            0,
                            constraints.maxHeight - (compact ? 24 : 48),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TweenAnimationBuilder<double>(
                              key: const ValueKey('boot-logo-motion'),
                              tween: Tween(begin: reduceMotion ? 0.0 : 8.0, end: 0.0),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 460),
                              curve: Curves.easeOutCubic,
                              builder: (context, offset, child) =>
                                  Transform.translate(offset: Offset(0, offset), child: child),
                              child: RepaintBoundary(child: _BootLogo(size: logoSize)),
                            ),
                            SizedBox(height: compact ? 18 : 27),
                            const Column(
                              children: [
                                Text(
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
                                SizedBox(height: 9),
                                Text(
                                  'منظومة ذكية لإدارة عمليات النظافة',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF154E43),
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
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
                            SizedBox(height: compact ? 24 : 35),
                            SizedBox(
                              width: 205,
                              child: Column(
                                children: [
                                  RepaintBoundary(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: reduceMotion
                                          ? const SizedBox(
                                              height: 5,
                                              width: double.infinity,
                                              child: ColoredBox(color: Color(0xFF0F9C7D)),
                                            )
                                          : const LinearProgressIndicator(
                                              minHeight: 5,
                                              backgroundColor: Color(0xFFC4E9D9),
                                              color: Color(0xFF0F9C7D),
                                            ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'ar'
                        ? 'تطوير: إيمان القهوجي'
                        : 'Developed by @Eman Al-Qahwaji',
                    key: const ValueKey('boot-developer-credit'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF528278),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BootLogo extends StatelessWidget {
  final double size;
  const _BootLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final ringSize = size + 35;
    const padding = 13.0;
    final decodeWidth = ((size - padding * 2) *
            MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: ringSize + 48,
          height: ringSize + 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0x4842CCA2), Color(0x1473DDC3), Color(0x0073DDC3)],
            ),
            border: Border.all(color: const Color(0xFFBDE9D8), width: 1.5),
          ),
        ),
        Container(
          width: ringSize,
          height: ringSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFDDF5E9),
            border: Border.all(color: const Color(0xFFC4EBD9)),
          ),
        ),
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: const Color(0xFFE5F3EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x28348F75),
                blurRadius: 25,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Image.asset(
            'assets/brand/cleanops_icon_new.png',
            cacheWidth: decodeWidth,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'CleanOps',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF087F6B),
                ),
              ),
            ),
          ),
        ),
        const PositionedDirectional(
          top: 6,
          end: 0,
          child: _BootBubble(icon: Icons.recycling_rounded, color: Color(0xFF088F75)),
        ),
        const PositionedDirectional(
          bottom: 2,
          start: 1,
          child: _BootBubble(icon: Icons.local_shipping_rounded, color: Color(0xFF288DA7)),
        ),
      ],
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
      gradient: LinearGradient(
        colors: [Color.lerp(color, Colors.white, .22)!, color],
      ),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2.5),
      boxShadow: const [BoxShadow(color: Color(0x1E0C755F), blurRadius: 11)],
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
                Text(
                  entry.$2,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF27574D),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BootBackdrop extends CustomPainter {
  const _BootBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Paint()..color = const Color(0x3DA7DFC8);
    canvas.drawCircle(
      Offset(size.width * .94, size.height * .13),
      size.width * .31,
      circle,
    );
    canvas.drawCircle(
      Offset(size.width * .04, size.height * .76),
      size.width * .37,
      circle,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x6653B89A);
    final center = Offset(size.width * .5, size.height * .37);
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (.28 + i * .12);
      canvas.drawCircle(center, radius, line);
    }
    final small = Paint()..color = const Color(0x6677C8A8);
    for (var i = 0; i < 12; i++) {
      final radians = math.pi * 2 * i / 12;
      final p =
          center +
          Offset(
            math.cos(radians) * size.width * .46,
            math.sin(radians) * size.width * .46,
          );
      canvas.drawCircle(p, 2 + i % 3, small);
    }
  }

  @override
  bool shouldRepaint(covariant _BootBackdrop oldDelegate) => false;
}
