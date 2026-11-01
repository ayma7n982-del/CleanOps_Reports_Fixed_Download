import 'package:flutter/material.dart';

/// Compact identity for the assistant using the user-approved truck/bin brand.
/// Intrinsic height keeps text readable with accessibility font sizes.
class AssistantHeroBanner extends StatelessWidget {
  const AssistantHeroBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD2F5E8), Color(0xFFE7FBF5)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF91DCC7)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/brand/cleanops_icon_new.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
                semanticLabel: 'شعار CleanOps',
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.recycling_rounded,
                      color: Color(0xFF07856D), size: 36),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مساعدك الذكي لإدارة عمليات النظافة',
                    style: TextStyle(
                      color: Color(0xFF103B38),
                      fontWeight: FontWeight.w900,
                      height: 1.4,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'اسأل عن التشغيل والتنبيهات والتقارير',
                    style: TextStyle(
                      color: Color(0xFF44716C),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
