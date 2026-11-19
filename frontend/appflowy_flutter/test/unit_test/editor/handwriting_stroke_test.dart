import 'package:appflowy/plugins/document/presentation/editor_plugins/handwriting/handwriting_stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HandwritingStroke', () {
    test('round-trips through JSON', () {
      final builder = HandwritingStrokeBuilder(
        tool: HandwritingTool.highlighter,
        color: 0xFFFFEB3B,
        width: 24,
      )
        ..add(10.04, 20.06, 0.123)
        ..add(50, 60, 0.9);
      final stroke = builder.build();

      final decoded = HandwritingStroke.fromJson(stroke.toJson())!;
      expect(decoded.tool, HandwritingTool.highlighter);
      expect(decoded.color, 0xFFFFEB3B);
      expect(decoded.width, 24);
      // Points are rounded to keep documents small.
      expect(decoded.points, [10.0, 20.1, 0.12, 50.0, 60.0, 0.9]);
    });

    test('skips points closer than the minimum distance', () {
      final builder = HandwritingStrokeBuilder(
        tool: HandwritingTool.pen,
        color: kHandwritingAutoColor,
        width: 4,
      )
        ..add(0, 0, 0.5)
        ..add(0.5, 0.5, 0.5)
        ..add(10, 0, 0.5);
      expect(builder.build().pointCount, 2);
    });

    test('ignores malformed data from the document', () {
      expect(HandwritingStroke.fromJson(null), isNull);
      expect(HandwritingStroke.fromJson({'p': 'x'}), isNull);
      expect(HandwritingStroke.fromJson({'p': [1, 2]}), isNull);
      expect(
        HandwritingStroke.listFromJson([
          {'p': [1, 2, 0.5]},
          'garbage',
          {
            'p': [1, 2, 0.5, 3, 4],
          },
        ]).map((s) => s.pointCount),
        [1, 1],
      );
      expect(HandwritingStroke.listFromJson('nope'), isEmpty);
    });

    test('hit test finds strokes near the eraser', () {
      const stroke = HandwritingStroke(
        tool: HandwritingTool.pen,
        color: kHandwritingAutoColor,
        width: 4,
        points: [0, 0, 0.5, 100, 0, 0.5],
      );
      expect(stroke.hitTest(50, 5, 5), isTrue);
      expect(stroke.hitTest(50, 30, 5), isFalse);
      expect(stroke.hitTest(110, 0, 5), isFalse);
    });
  });
}
