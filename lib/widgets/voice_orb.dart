import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/gemini_live_service.dart';

class VoiceOrb extends StatefulWidget {
  final LiveVoiceState state;
  final bool isActive;
  final VoidCallback? onTap;

  const VoiceOrb({
    super.key,
    required this.state,
    this.isActive = false,
    this.onTap,
  });

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _barsCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _barsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _barsCtrl.dispose();
    super.dispose();
  }

  Color _orbColor() {
    switch (widget.state) {
      case LiveVoiceState.idle:
        return const Color(0xFF6366F1);
      case LiveVoiceState.connecting:
        return const Color(0xFFF59E0B);
      case LiveVoiceState.listening:
        return const Color(0xFF10B981);
      case LiveVoiceState.speaking:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _orbColor();
    final isListening = widget.state == LiveVoiceState.listening;
    final isSpeaking = widget.state == LiveVoiceState.speaking;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseCtrl, _barsCtrl]),
        builder: (context, _) {
          final pulse = _pulseCtrl.value;
          final barPhase = _barsCtrl.value;

          final scale = widget.isActive ? 1.0 + pulse * 0.06 : 1.0;
          final glow = widget.isActive ? pulse * 20.0 : 8.0;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: widget.isActive ? 0.35 : 0.12),
                    blurRadius: glow,
                    spreadRadius: widget.isActive ? 4 : 1,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isListening)
                    ...List.generate(5, (i) {
                      final barHeight = 16 + math.sin(barPhase * 2 * math.pi + i * 1.2).abs() * 30;
                      return Positioned(
                        bottom: 50,
                        left: 60 + i * 10.0,
                        child: Container(
                          width: 4,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  if (isSpeaking)
                    ...List.generate(5, (i) {
                      final barHeight = 20 + math.sin(barPhase * 2 * math.pi + i * 1.2).abs() * 20;
                      return Positioned(
                        bottom: 50,
                        left: 60 + i * 10.0,
                        child: Container(
                          width: 4,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  Icon(
                    Icons.graphic_eq,
                    size: 48,
                    color: widget.isActive
                        ? Colors.white
                        : color.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
