import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// A swipe-to-confirm button. Calls [onConfirmed] when user swipes ≥ 80% right.
class SlideToStartButton extends StatefulWidget {
  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final bool loading;

  const SlideToStartButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.loading = false,
  });

  @override
  State<SlideToStartButton> createState() => _SlideToStartButtonState();
}

class _SlideToStartButtonState extends State<SlideToStartButton>
    with SingleTickerProviderStateMixin {
  double _dragX = 0;
  static const double _thumbSize = 56;
  static const double _threshold = 0.80;
  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d, double trackWidth) {
    if (!widget.enabled || widget.loading) return;
    final maxDrag = trackWidth - _thumbSize;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0, maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails d, double trackWidth) {
    final maxDrag = trackWidth - _thumbSize;
    final progress = maxDrag > 0 ? _dragX / maxDrag : 0;
    if (progress >= _threshold) {
      widget.onConfirmed();
      setState(() => _dragX = maxDrag.toDouble());
    } else {
      setState(() => _dragX = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = (trackWidth - _thumbSize).clamp(0.0, double.infinity);
        final progress = maxDrag > 0 ? (_dragX / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: widget.enabled
                ? LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.1),
                      AppColors.primary.withOpacity(0.05),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: widget.enabled ? null : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.enabled
                  ? AppColors.primary.withOpacity(0.3)
                  : Colors.grey.shade300,
              width: 1.5,
            ),
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Progress fill with gradient
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: (_dragX + _thumbSize).clamp(0.0, trackWidth),
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.25 * progress),
                      AppColors.primary.withOpacity(0.15 * progress),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              // Animated arrows indicator
              if (widget.enabled && !widget.loading && _pulseAnimation != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation!,
                    builder: (context, child) {
                      return Padding(
                        padding: EdgeInsets.only(
                          left: _thumbSize + 16 + (_pulseAnimation!.value * 8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppColors.primary.withOpacity(
                                0.3 + (_pulseAnimation!.value * 0.3),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppColors.primary.withOpacity(
                                0.2 + (_pulseAnimation!.value * 0.3),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: AppColors.primary.withOpacity(
                                0.1 + (_pulseAnimation!.value * 0.2),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              // Label
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(left: _thumbSize + 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          )
                        : Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: widget.enabled
                                  ? AppColors.primary
                                  : Colors.grey,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ),
              // Thumb with modern design
              GestureDetector(
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, trackWidth),
                onHorizontalDragEnd: (d) => _onDragEnd(d, trackWidth),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  margin: EdgeInsets.only(left: _dragX + 4),
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: BoxDecoration(
                    gradient: widget.enabled
                        ? LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withOpacity(0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: widget.enabled ? null : Colors.grey,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: widget.enabled
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Main arrow icon
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      // Additional right arrow for emphasis
                      Positioned(
                        right: 8,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(0.6),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
