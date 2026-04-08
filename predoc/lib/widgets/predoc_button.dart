import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PredocButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isOutlined;
  final bool isFullWidth;
  final IconData? suffixIcon;
  final Color? backgroundColor;
  final Color? textColor;

  const PredocButton({
    super.key,
    required this.label,
    this.onTap,
    this.isOutlined = false,
    this.isFullWidth = true,
    this.suffixIcon,
    this.backgroundColor,
    this.textColor,
  });

  @override
  State<PredocButton> createState() => _PredocButtonState();
}

class _PredocButtonState extends State<PredocButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.04,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ??
        (widget.isOutlined ? Colors.transparent : AppColors.primary);
    final fgColor = widget.textColor ??
        (widget.isOutlined ? AppColors.primary : Colors.white);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: Container(
          width: widget.isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(50),
            border: widget.isOutlined
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
            boxShadow: widget.isOutlined
                ? null
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize:
                widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: fgColor,
                  letterSpacing: 0.3,
                ),
              ),
              if (widget.suffixIcon != null) ...[
                const SizedBox(width: 10),
                Icon(widget.suffixIcon, color: fgColor, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
