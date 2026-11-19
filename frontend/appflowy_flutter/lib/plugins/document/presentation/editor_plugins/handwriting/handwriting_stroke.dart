import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Strokes are stored in a fixed reference coordinate space that is
/// [kHandwritingReferenceWidth] units wide, and scaled to the real canvas
/// width when rendered. This keeps handwriting in place when the same
/// document is opened on screens of different sizes or orientations.
const double kHandwritingReferenceWidth = 1000;

/// Color value meaning "use the theme's text color" (black in light mode,
/// white in dark mode).
const int kHandwritingAutoColor = 0;

enum HandwritingTool { pen, highlighter, eraser }

class HandwritingStroke {
  const HandwritingStroke({
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  /// Pen or highlighter (the eraser never produces strokes).
  final HandwritingTool tool;

  /// ARGB color, or [kHandwritingAutoColor].
  final int color;

  /// Base width in reference units.
  final double width;

  /// Flat list of x, y, pressure triples in reference units.
  /// Pressure is normalized to 0..1.
  final List<double> points;

  int get pointCount => points.length ~/ 3;

  bool get isHighlighter => tool == HandwritingTool.highlighter;

  static const _keyTool = 't';
  static const _keyColor = 'c';
  static const _keyWidth = 'w';
  static const _keyPoints = 'p';

  Map<String, dynamic> toJson() => {
        _keyTool: isHighlighter ? 'h' : 'p',
        _keyColor: color,
        _keyWidth: width,
        _keyPoints: points,
      };

  static HandwritingStroke? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final rawPoints = json[_keyPoints];
    if (rawPoints is! List || rawPoints.length < 3) {
      return null;
    }
    final points = <double>[];
    for (final value in rawPoints) {
      if (value is! num) {
        return null;
      }
      points.add(value.toDouble());
    }
    points.length -= points.length % 3;
    final color = json[_keyColor];
    final width = json[_keyWidth];
    return HandwritingStroke(
      tool: json[_keyTool] == 'h'
          ? HandwritingTool.highlighter
          : HandwritingTool.pen,
      color: color is num ? color.toInt() : kHandwritingAutoColor,
      width: width is num ? width.toDouble() : 4,
      points: points,
    );
  }

  static List<HandwritingStroke> listFromJson(Object? json) {
    if (json is! List) {
      return const [];
    }
    return json
        .map(HandwritingStroke.fromJson)
        .whereType<HandwritingStroke>()
        .toList(growable: false);
  }

  /// Whether a circle at ([x], [y]) with [radius] (reference units) touches
  /// this stroke.
  bool hitTest(double x, double y, double radius) {
    final reach = radius + width / 2;
    final reachSquared = reach * reach;
    if (pointCount == 1) {
      return _distanceSquared(x, y, points[0], points[1]) <= reachSquared;
    }
    for (var i = 0; i < pointCount - 1; i++) {
      final ax = points[i * 3];
      final ay = points[i * 3 + 1];
      final bx = points[i * 3 + 3];
      final by = points[i * 3 + 4];
      if (_segmentDistanceSquared(x, y, ax, ay, bx, by) <= reachSquared) {
        return true;
      }
    }
    return false;
  }

  static double _distanceSquared(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return dx * dx + dy * dy;
  }

  static double _segmentDistanceSquared(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) {
      return _distanceSquared(px, py, ax, ay);
    }
    final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0, 1);
    return _distanceSquared(px, py, ax + t * dx, ay + t * dy);
  }
}

/// Builds a stroke point by point while the pen is down.
class HandwritingStrokeBuilder {
  HandwritingStrokeBuilder({
    required this.tool,
    required this.color,
    required this.width,
  });

  final HandwritingTool tool;
  final int color;
  final double width;
  final List<double> points = [];

  /// Minimum distance between recorded points, in reference units. Keeps the
  /// saved document small without visibly changing the line.
  static const double _minDistance = 1.5;

  void add(double x, double y, double pressure) {
    final n = points.length;
    if (n >= 3) {
      final dx = x - points[n - 3];
      final dy = y - points[n - 2];
      if (dx * dx + dy * dy < _minDistance * _minDistance) {
        return;
      }
    }
    points
      ..add(_round(x, 10))
      ..add(_round(y, 10))
      ..add(_round(pressure.clamp(0, 1), 100));
  }

  bool get isEmpty => points.isEmpty;

  HandwritingStroke build() => HandwritingStroke(
        tool: tool,
        color: color,
        width: width,
        points: List.unmodifiable(points),
      );

  static double _round(double value, int factor) =>
      (value * factor).roundToDouble() / factor;
}

/// Draws strokes onto a canvas.
class HandwritingStrokePainter {
  const HandwritingStrokePainter._();

  static void paint(
    Canvas canvas,
    HandwritingStroke stroke, {
    required double scale,
    required Color autoColor,
  }) {
    if (stroke.points.isEmpty) {
      return;
    }
    final baseColor = stroke.color == kHandwritingAutoColor
        ? autoColor
        : Color(stroke.color);
    if (stroke.isHighlighter) {
      _paintHighlighter(canvas, stroke, scale, baseColor);
    } else {
      _paintPen(canvas, stroke, scale, baseColor);
    }
  }

  static double _pressureFactor(double pressure) => 0.35 + 0.9 * pressure;

  static void _paintPen(
    Canvas canvas,
    HandwritingStroke stroke,
    double scale,
    Color color,
  ) {
    final p = stroke.points;
    final count = stroke.pointCount;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (count == 1) {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(p[0] * scale, p[1] * scale),
        stroke.width * scale * _pressureFactor(p[2]) / 2,
        paint,
      );
      return;
    }

    // Smooth the line with quadratic curves through segment midpoints, and
    // vary the width of each piece with pen pressure.
    var startX = p[0] * scale;
    var startY = p[1] * scale;
    for (var i = 1; i < count; i++) {
      final cx = p[i * 3] * scale;
      final cy = p[i * 3 + 1] * scale;
      final isLast = i == count - 1;
      final endX = isLast ? cx : (cx + p[i * 3 + 3] * scale) / 2;
      final endY = isLast ? cy : (cy + p[i * 3 + 4] * scale) / 2;
      final pressure = (p[i * 3 - 1] + p[i * 3 + 2]) / 2;
      paint.strokeWidth =
          math.max(0.5, stroke.width * scale * _pressureFactor(pressure));
      final path = Path()
        ..moveTo(startX, startY)
        ..quadraticBezierTo(cx, cy, endX, endY);
      canvas.drawPath(path, paint);
      startX = endX;
      startY = endY;
    }
  }

  static void _paintHighlighter(
    Canvas canvas,
    HandwritingStroke stroke,
    double scale,
    Color color,
  ) {
    final p = stroke.points;
    final count = stroke.pointCount;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.width * scale
      ..isAntiAlias = true;

    // A single path, so overlapping parts of one stroke don't get darker.
    final path = Path()..moveTo(p[0] * scale, p[1] * scale);
    if (count == 1) {
      path.lineTo(p[0] * scale + 0.1, p[1] * scale);
    }
    for (var i = 1; i < count; i++) {
      path.lineTo(p[i * 3] * scale, p[i * 3 + 1] * scale);
    }
    canvas.drawPath(path, paint);
  }
}

/// Paints a list of finished strokes. Kept separate from the stroke being
/// drawn so the (possibly large) finished set is not repainted on every
/// pointer move.
class HandwritingStrokesCustomPainter extends CustomPainter {
  HandwritingStrokesCustomPainter({
    required this.strokes,
    required this.scale,
    required this.autoColor,
    this.hidden = const {},
  });

  final List<HandwritingStroke> strokes;
  final double scale;
  final Color autoColor;

  /// Indexes of strokes to skip (being erased).
  final Set<int> hidden;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < strokes.length; i++) {
      if (hidden.contains(i)) {
        continue;
      }
      HandwritingStrokePainter.paint(
        canvas,
        strokes[i],
        scale: scale,
        autoColor: autoColor,
      );
    }
  }

  @override
  bool shouldRepaint(HandwritingStrokesCustomPainter oldDelegate) =>
      !identical(strokes, oldDelegate.strokes) ||
      scale != oldDelegate.scale ||
      autoColor != oldDelegate.autoColor ||
      hidden.length != oldDelegate.hidden.length;
}

/// Paints the stroke currently being drawn.
class HandwritingActiveStrokePainter extends CustomPainter {
  HandwritingActiveStrokePainter({
    required this.builder,
    required this.scale,
    required this.autoColor,
    required super.repaint,
  });

  final HandwritingStrokeBuilder? Function() builder;
  final double scale;
  final Color autoColor;

  @override
  void paint(Canvas canvas, Size size) {
    final active = builder();
    if (active == null || active.isEmpty) {
      return;
    }
    canvas.clipRect(Offset.zero & size);
    HandwritingStrokePainter.paint(
      canvas,
      active.build(),
      scale: scale,
      autoColor: autoColor,
    );
  }

  @override
  bool shouldRepaint(HandwritingActiveStrokePainter oldDelegate) => true;
}
