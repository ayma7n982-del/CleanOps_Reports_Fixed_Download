import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An original, vector-only eco-assistant illustration. No downloads,
/// packages, Firebase reads, or animation controllers are needed.
class AssistantHeroBanner extends StatelessWidget {
  const AssistantHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 370;
    final illustrationWidth = narrow ? 104.0 : 142.0;
    return Semantics(
      label: 'مساعد ذكي لإدارة عمليات النظافة',
      child: Container(
        height: narrow ? 177 : 191,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD2F5E8), Color(0xFFE7FBF5), Color(0xFFF4FBF7)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: const Color(0xFF91DCC7).withOpacity(.52)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x132A9884),
              blurRadius: 18,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _EcoLandscapePainter())),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(narrow ? 8 : 12, 10, 15, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: illustrationWidth,
                    height: double.infinity,
                    child: const CustomPaint(painter: _EcoRobotPainter()),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مساعدك الذكي لإدارة عمليات النظافة',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFF103B38),
                            fontWeight: FontWeight.w900,
                            height: 1.28,
                            fontSize: narrow ? 15 : 17,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'تحليلات وتنبيهات وتقارير من بياناتك الفعلية',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFF44716C),
                            fontSize: narrow ? 10 : 11,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCF7E9),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: const Color(0xFFA4DDC9)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF07856D)),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'بيانات ذكية لمدن أنظف',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF126C5B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EcoLandscapePainter extends CustomPainter {
  const _EcoLandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final distant = Paint()..color = const Color(0x4476CAB7);
    final lawn = Paint()..color = const Color(0x3395D8B5);
    canvas.drawOval(
      Rect.fromLTWH(-35, size.height - 46, size.width + 95, 110), lawn,
    );
    for (var i = 0; i < 8; i++) {
      final x = size.width * (.05 + i * .13);
      final top = size.height * (.62 - (i % 3) * .05);
      final width = 12.0 + (i % 3) * 4.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, top, width, size.height - top),
            const Radius.circular(4)),
        distant,
      );
    }
    final dots = Paint()..color = const Color(0x2298D8C7);
    for (var i = 0; i < 9; i++) {
      final x = size.width * (.12 + i * .105);
      final y = size.height * (.17 + (i % 4) * .12);
      canvas.drawCircle(Offset(x, y), 2.1 + (i % 3), dots);
    }
  }

  @override
  bool shouldRepaint(covariant _EcoLandscapePainter oldDelegate) => false;
}

class _EcoRobotPainter extends CustomPainter {
  const _EcoRobotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 160, size.height / 190);
    final shadow = Paint()..color = const Color(0x4051B69D)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13);
    final outline = Paint()..color = const Color(0xFFBCD9D7);
    final white = Paint()..color = Colors.white;
    final mint = Paint()..color = const Color(0xFF04A786);
    final dark = Paint()..color = const Color(0xFF073E47);
    final leaf = Paint()..color = const Color(0xFF21AF75);
    final leafLight = Paint()..color = const Color(0xFF72D794);

    canvas.drawOval(const Rect.fromLTWH(21, 166, 118, 14), shadow);
    // Recycling-bin and soft foliage silhouettes behind the robot.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(122, 115, 27, 43), const Radius.circular(5)),
      leaf,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(118, 107, 36, 9), const Radius.circular(4)),
      mint,
    );
    final recycle = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(136, 134), 8, recycle);
    canvas.drawArc(const Rect.fromLTWH(131, 129, 10, 10), -.4, math.pi * 1.6, false, mint..strokeWidth = 2.1..style = PaintingStyle.stroke);
    mint.style = PaintingStyle.fill;

    // Body, chest insert and short legs.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(54, 94, 66, 73), const Radius.circular(29)),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(57, 96, 60, 68), const Radius.circular(27)),
      white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(72, 112, 32, 33), const Radius.circular(12)),
      leafLight,
    );
    canvas.drawCircle(const Offset(88, 125), 10, mint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(67, 157, 14, 20), const Radius.circular(7)), outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(99, 157, 14, 20), const Radius.circular(7)), outline,
    );

    // Stylized arms.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(37, 109, 20, 42), const Radius.circular(10)), outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(118, 105, 19, 44), const Radius.circular(9)), outline,
    );
    canvas.drawCircle(const Offset(45, 148), 11, white);
    canvas.drawCircle(const Offset(127, 145), 10, white);

    // Head enclosure and ear pods.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(36, 29, 103, 82), const Radius.circular(28)), outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(39, 32, 96, 76), const Radius.circular(27)), white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(47, 41, 80, 57), const Radius.circular(20)), dark,
    );
    canvas.drawCircle(const Offset(39, 71), 12, mint);
    canvas.drawCircle(const Offset(135, 71), 12, mint);
    // Happy eyes, expressive mouth, and glossy screen.
    final face = Paint()..color = const Color(0xFF58E8B8)
      ..strokeWidth = 3.6..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    canvas.drawArc(const Rect.fromLTWH(66, 65, 15, 12), math.pi, math.pi, false, face);
    canvas.drawArc(const Rect.fromLTWH(98, 65, 15, 12), math.pi, math.pi, false, face);
    canvas.drawArc(const Rect.fromLTWH(82, 77, 14, 9), .08, math.pi - .16, false, face);
    face.style = PaintingStyle.fill;
    canvas.drawOval(const Rect.fromLTWH(54, 46, 31, 5), Paint()..color = const Color(0x338FECE4));

    // Leaf antenna.
    canvas.drawLine(const Offset(88, 28), const Offset(94, 13),
        Paint()..color = const Color(0xFF0E9771)..strokeWidth = 3..strokeCap = StrokeCap.round);
    final blade = Path()
      ..moveTo(94, 14)
      ..quadraticBezierTo(100, -3, 115, 6)
      ..quadraticBezierTo(108, 23, 94, 14);
    canvas.drawPath(blade, leaf);
    canvas.save();
    canvas.translate(22, 86);
    canvas.rotate(-.45);
    final sideLeaf = Path()
      ..moveTo(0, 0)..quadraticBezierTo(-20, -15, -17, -40)
      ..quadraticBezierTo(10, -32, 0, 0);
    canvas.drawPath(sideLeaf, leafLight);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EcoRobotPainter oldDelegate) => false;
}
