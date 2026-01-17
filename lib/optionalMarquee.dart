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

        // ✅ 修正：移除 height: 0，改用標準行高 (null 或 1.x)
        // 如果傳入 height: 0，我們覆蓋它，因為這會導致渲染問題
        final TextStyle effectiveStyle = style.copyWith(
          height: style.height == 0 ? 1.2 : style.height, // 強制一個合理的行高
          leadingDistribution: TextLeadingDistribution.even, // 解決中文偏移
        );

        final textPainter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);

        final bool overflows = textPainter.width > maxWidth;
        final double textHeight = textPainter.height;

        // 我們使用 Stack 技巧來確保對齊
        // 底層放一個隱藏的 Text 來撐開高度和基線
        // 上層放 Marquee 或 Text
        return Container(
          width: maxWidth,
          height: textHeight,
          alignment: Alignment.centerLeft,
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
                ),
        );
      },
    );
  }
}
