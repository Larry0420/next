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
    this.blankSpace = 20.0,
    this.velocity = 30.0,
    this.pauseAfterRound = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 🔴 檢查約束是否有效
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0 || constraints.maxWidth.isInfinite) {
          return Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        // 使用 TextPainter 計算文字寬度
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);

        // 檢查是否超過容器寬度
        final bool overflows = textPainter.width > constraints.maxWidth;

        if (overflows) {
          // 🔴 使用精確的行高計算，與靜態 Text 一致
          final double lineHeight = (style.fontSize ?? 14.0) * (style.height ?? 1.2);

          return SizedBox(
            width: constraints.maxWidth, // 🔴 必須明確設定寬度，防止佈局錯誤
            height: lineHeight, // 🔴 使用計算出的行高
            child: Marquee(
              text: text,
              style: style,
              scrollAxis: scrollAxis,
              crossAxisAlignment: CrossAxisAlignment.center, // 🔴 改成 center 確保垂直居中
              blankSpace: blankSpace,
              velocity: velocity,
              pauseAfterRound: pauseAfterRound,
              startPadding: 0.0,
              accelerationDuration: Duration(seconds: 1),
              accelerationCurve: Curves.linear,
              decelerationDuration: Duration(milliseconds: 500),
              decelerationCurve: Curves.easeOut,
            ),
          );
        } else {
          // 否則顯示靜態文字
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
