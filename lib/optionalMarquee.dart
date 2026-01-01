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
    Key? key,
    required this.text,
    required this.style,
    this.scrollAxis = Axis.horizontal,
    this.blankSpace = 30.0,
    this.velocity = 120.0,
    this.pauseAfterRound = const Duration(seconds: 1),
    this.width,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = width ?? constraints.maxWidth;

        // 定義統一的 StrutStyle，強制行高一致
        // forceStrutHeight: true 是關鍵
        final StrutStyle strutStyle = StrutStyle.fromTextStyle(
          style,
          forceStrutHeight: true, 
        );

        if (maxWidth <= 0 || maxWidth.isInfinite) {
          return Text(
            text,
            style: style,
            strutStyle: strutStyle, // 套用 StrutStyle
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          strutStyle: strutStyle, // 測量時也套用 StrutStyle
        )..layout(maxWidth: double.infinity);

        final bool overflows = textPainter.width > maxWidth;
        
        // 使用含有 strutStyle 的 textPainter 測量出的高度
        final double textHeight = textPainter.height;

        if (overflows) {
          return SizedBox(
            width: maxWidth,
            height: textHeight,
            child: Marquee(
              text: text,
              style: style,
              scrollAxis: scrollAxis,
              crossAxisAlignment: CrossAxisAlignment.start,
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
          return SizedBox(
            width: maxWidth,
            height: textHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: style,
                strutStyle: strutStyle, // 套用 StrutStyle
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }
      },
    );
  }
}
