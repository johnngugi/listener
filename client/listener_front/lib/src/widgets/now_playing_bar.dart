import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/widgets/album_art.dart';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        color: panelColor,
        border: Border(top: BorderSide(color: lineColor)),
      ),
      child: Row(
        children: const [
          SizedBox(width: 20),
          AlbumArt(style: CoverStyle.sunset, size: 78),
          SizedBox(width: 18),
          SizedBox(width: 270, child: NowPlayingText()),
          Spacer(),
          TransportControls(),
          Spacer(),
          OutputControl(),
          SizedBox(width: 32),
        ],
      ),
    );
  }
}

class NowPlayingText extends StatelessWidget {
  const NowPlayingText({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hotel California',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Eagles',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class TransportControls extends StatelessWidget {
  const TransportControls({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 820,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.fiber_manual_record,
                color: Color(0xFF656568),
                size: 14,
              ),
              SizedBox(width: 62),
              Icon(Icons.skip_previous, color: textColor, size: 28),
              SizedBox(width: 34),
              Icon(Icons.play_arrow, color: textColor, size: 40),
              SizedBox(width: 34),
              Icon(Icons.skip_next, color: textColor, size: 28),
              SizedBox(width: 52),
              Icon(Icons.queue_music, color: textColor, size: 24),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text(
                '0:10',
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: CustomPaint(painter: WaveformPainter()),
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                '6:31',
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  const WaveformPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height / 2;
    final paint = Paint()
      ..color = mutedColor.withValues(alpha: .28)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 190; i++) {
      final x = i * size.width / 190;
      final envelope =
          math.sin(i * .1).abs() * .55 + math.sin(i * .031).abs() * .45;
      final h = size.height * (.1 + envelope * .36);
      canvas.drawLine(
        Offset(x, baseline - h / 2),
        Offset(x, baseline + h / 2),
        paint,
      );
    }

    final playedPaint = Paint()
      ..color = accentColor.withValues(alpha: .72)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 12; i++) {
      final x = i * size.width / 190;
      final h = size.height * (.14 + math.sin(i * .7).abs() * .38);
      canvas.drawLine(
        Offset(x, baseline - h / 2),
        Offset(x, baseline + h / 2),
        playedPaint,
      );
    }

    canvas.drawLine(
      Offset(size.width * .028, 0),
      Offset(size.width * .028, size.height),
      Paint()
        ..color = const Color(0xFFFF2C75)
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OutputControl extends StatelessWidget {
  const OutputControl({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.speaker, color: textColor, size: 38),
              SizedBox(height: 8),
              Text(
                'System Output',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 36),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.volume_up_outlined, color: textColor, size: 38),
              SizedBox(height: 9),
              Text(
                '100',
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
