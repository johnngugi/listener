import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:listener_front/src/models/track.dart';

class AlbumArt extends StatelessWidget {
  const AlbumArt({super.key, required this.style, this.size = 74});

  final CoverStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: style.base,
        border: Border.all(color: Colors.black.withValues(alpha: .25)),
      ),
      child: CustomPaint(painter: AlbumArtPainter(style)),
    );
  }
}

class AlbumArtPainter extends CustomPainter {
  const AlbumArtPainter(this.style);

  final CoverStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();

    switch (style) {
      case CoverStyle.sky:
        paint.shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF28C5ED), Color(0xFFB7EEFF), Color(0xFFF2D04C)],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
        paint.shader = null;
        paint.color = Colors.white.withValues(alpha: .55);
        for (var i = 0; i < 9; i++) {
          canvas.drawCircle(
            Offset(
              size.width * (.1 + i * .1),
              size.height * (.18 + (i % 2) * .05),
            ),
            1.4,
            paint,
          );
        }
        paint.color = const Color(0xFF1B1B23);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * .54, size.height * .48),
            width: size.width * .28,
            height: size.height * .44,
          ),
          paint,
        );
        paint.color = const Color(0xFFE8CDB5);
        canvas.drawCircle(Offset(size.width * .5, size.height * .28), 7, paint);
        paint.color = const Color(0xFFEBF2F4);
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(size.width * .5, size.height * .7),
            width: size.width * .64,
            height: size.height * .42,
          ),
          math.pi,
          math.pi,
          true,
          paint,
        );
      case CoverStyle.eclipse:
        paint.shader = const RadialGradient(
          colors: [Color(0xFFFA3434), Color(0xFF050505)],
          stops: [.16, .62],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
        paint.shader = null;
        paint.color = Colors.black;
        canvas.drawCircle(size.center(Offset.zero), size.width * .25, paint);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFF9C1A);
        canvas.drawCircle(size.center(Offset.zero), size.width * .3, paint);
      case CoverStyle.mist:
        paint.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF8F8), Color(0xFF8FC1D2), Color(0xFFF9FBFC)],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
        paint.shader = null;
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: .85);
        canvas.drawLine(
          Offset(size.width * .08, size.height * .84),
          Offset(size.width * .9, size.height * .2),
          paint,
        );
        paint
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF10141B);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * .55, size.height * .48),
            width: size.width * .18,
            height: size.height * .44,
          ),
          paint,
        );
      case CoverStyle.monochrome:
        paint.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF050505), Color(0xFF777777), Color(0xFFE8E8E8)],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
        paint.shader = null;
        paint.color = Colors.white.withValues(alpha: .55);
        canvas.drawCircle(size.center(Offset.zero), size.width * .32, paint);
        paint.color = Colors.black.withValues(alpha: .72);
        canvas.drawCircle(size.center(Offset.zero), size.width * .2, paint);
      case CoverStyle.street:
        paint.shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF222416), Color(0xFF050607)],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
        paint.shader = null;
        paint.color = const Color(0xFF303336);
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * .08,
            size.height * .38,
            size.width * .84,
            size.height * .34,
          ),
          paint,
        );
        paint.color = const Color(0xFFBBC027);
        canvas.drawPath(
          Path()
            ..moveTo(size.width * .05, size.height * .12)
            ..lineTo(size.width * .33, size.height * .12)
            ..lineTo(size.width * .27, size.height * .28)
            ..lineTo(size.width * .09, size.height * .28)
            ..close(),
          paint,
        );
        paint.color = const Color(0xFFDFD7C7);
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * .68,
            size.height * .49,
            size.width * .14,
            size.height * .1,
          ),
          paint,
        );
      case CoverStyle.wave:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF031011));
        _drawWave(canvas, size, Colors.white.withValues(alpha: .82), 2.2);
      case CoverStyle.sunset:
        paint.shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF9C46D),
            Color(0xFFE86245),
            Color(0xFF182C55),
            Color(0xFF08111F),
          ],
          stops: [0, .35, .7, 1],
        ).createShader(rect);
        canvas.drawRect(rect, paint);
        paint.shader = null;
        paint.color = const Color(0xFFFFE7A0);
        canvas.drawCircle(
          Offset(size.width * .36, size.height * .3),
          size.width * .15,
          paint,
        );
        paint.color = const Color(0xFF05070B);
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * .68, size.width, size.height * .32),
          paint,
        );
        paint.color = const Color(0xFF121C3B);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * .72, size.height * .82),
            width: size.width * .72,
            height: size.height * .2,
          ),
          paint,
        );
        _drawPalm(
          canvas,
          size,
          Offset(size.width * .18, size.height * .7),
          .82,
        );
        _drawPalm(
          canvas,
          size,
          Offset(size.width * .72, size.height * .72),
          .64,
        );
    }
  }

  void _drawWave(Canvas canvas, Size size, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 24; i++) {
      final x = size.width * (.08 + i * .036);
      final height = size.height * (.18 + .15 * math.sin(i * .9).abs());
      canvas.drawLine(
        Offset(x, size.height / 2 - height / 2),
        Offset(x, size.height / 2 + height / 2),
        paint,
      );
    }
  }

  void _drawPalm(Canvas canvas, Size size, Offset base, double scale) {
    final paint = Paint()
      ..color = const Color(0xFF05070B)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5 * scale;
    final top = Offset(
      base.dx + size.width * .06 * scale,
      base.dy - size.height * .48 * scale,
    );

    canvas.drawLine(base, top, paint);

    for (var i = 0; i < 7; i++) {
      final angle = -math.pi * .88 + i * math.pi * .27;
      final end = Offset(
        top.dx + math.cos(angle) * size.width * .2 * scale,
        top.dy + math.sin(angle) * size.height * .15 * scale,
      );
      canvas.drawLine(top, end, paint..strokeWidth = 2 * scale);
    }
  }

  @override
  bool shouldRepaint(covariant AlbumArtPainter oldDelegate) {
    return oldDelegate.style != style;
  }
}
