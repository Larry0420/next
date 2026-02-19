import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

class OptionalMarquee extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Axis scrollAxis;
  final double blankSpace;
  final double velocity;
  final Duration pauseAfterRound;
  final double? width;

  const OptionalMarquee({
    super.key,
    required this.text,
    required this.style,
    this.scrollAxis = Axis.horizontal,
    this.blankSpace = 30.0,
    this.velocity = 120.0,
    this.pauseAfterRound = const Duration(seconds: 1),
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = width ?? constraints.maxWidth;

        // Ensure proper height for descenders
        final TextStyle effectiveStyle = style.copyWith(
          height: style.height ?? 1.4, // Use 1.4 if not specified
          leadingDistribution: TextLeadingDistribution.even,
        );

        // Define consistent StrutStyle for both Marquee and Text
        final strutStyle = StrutStyle(
          fontSize: effectiveStyle.fontSize,
          height: effectiveStyle.height,
          forceStrutHeight: true,
          leading: 0.0,
        );

        final textPainter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          strutStyle: strutStyle,
        )..layout(maxWidth: double.infinity);

        final bool overflows = textPainter.width > maxWidth;

        // Use exact measured height (no multiplication)
        return SizedBox(
          width: maxWidth,
          height: textPainter.height, // No extra padding
          child: overflows
              ? Marquee(
                  text: text,
                  style: effectiveStyle,
                  scrollAxis: scrollAxis,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  blankSpace: blankSpace,
                  velocity: velocity,
                  pauseAfterRound: pauseAfterRound,
                  startPadding: 0.0,
                  accelerationDuration: const Duration(seconds: 1),
                  accelerationCurve: Curves.linear,
                  decelerationDuration: const Duration(milliseconds: 500),
                  decelerationCurve: Curves.easeOut,
                )
              : Text(
                  text,
                  style: effectiveStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  strutStyle: strutStyle, // Same strut as Marquee
                ),
        );
      },
    );
  }
}
