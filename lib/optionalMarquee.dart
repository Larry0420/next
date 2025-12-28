import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

class OptionalMarquee extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Axis scrollAxis;
  final double blankSpace;
  final double velocity;
  final Duration pauseAfterRound;

  const OptionalMarquee({
    Key? key,
    required this.text,
    required this.style,
    this.scrollAxis = Axis.horizontal,
    this.blankSpace = 30.0,
    this.velocity = 120.0,
    this.pauseAfterRound = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 🔴 Check for valid constraints
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0 || constraints.maxWidth.isInfinite) {
          return Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // Use TextPainter to calculate text dimensions
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);

        // Check overflow
        final bool overflows = textPainter.width > constraints.maxWidth;

        if (overflows) {
          // 🔴 Use textPainter.height to include descenders like 'g'
          // Add a small buffer (e.g., 2.0) if font metrics are tight
          final double computedHeight = textPainter.height;

          return SizedBox(
            width: constraints.maxWidth,
            height: computedHeight, 
            child: Marquee(
              text: text,
              style: style,
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
            ),
          );
        } else {
          // Show static text
          return Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
      },
    );
  }
}
