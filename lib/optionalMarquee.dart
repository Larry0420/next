import 'package:flutter/foundation.dart';
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
    if (kIsWeb) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = width ?? constraints.maxWidth;
        final TextStyle effectiveStyle = style.copyWith(
          height: style.height ?? 1.4,
          leadingDistribution: TextLeadingDistribution.even,
        );
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
        textPainter.dispose();

        return SizedBox(
          width: maxWidth,
          height: textPainter.height,
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
                  strutStyle: strutStyle,
                ),
        );
      },
    );
  }
}
