import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'handwriting_stroke.dart';

/// Pen settings shared by every handwriting block in the app, so switching
/// between blocks keeps the same pen, like picking up the same pen again.
class HandwritingToolController extends ChangeNotifier {
  HandwritingToolController._();

  static final HandwritingToolController instance =
      HandwritingToolController._();

  static const List<int> penColors = [
    kHandwritingAutoColor,
    0xFF2F6BFF, // blue
    0xFFE53935, // red
    0xFF2E7D32, // green
    0xFFFB8C00, // orange
    0xFF8E24AA, // purple
  ];

  static const List<int> highlighterColors = [
    0xFFFFEB3B, // yellow
    0xFF76FF03, // green
    0xFFFF4081, // pink
    0xFF40C4FF, // blue
  ];

  /// Thin, medium, thick in reference units.
  static const List<double> penWidths = [2, 4, 8];
  static const List<double> highlighterWidths = [14, 24, 36];

  HandwritingTool _tool = HandwritingTool.pen;
  HandwritingTool get tool => _tool;
  set tool(HandwritingTool value) => _update(() => _tool = value);

  int _penColor = penColors.first;
  int _highlighterColor = highlighterColors.first;
  int _penWidthIndex = 1;
  int _highlighterWidthIndex = 1;

  bool get _isHighlighter => _tool == HandwritingTool.highlighter;

  List<int> get colors => _isHighlighter ? highlighterColors : penColors;
  List<double> get widths => _isHighlighter ? highlighterWidths : penWidths;

  int get color => _isHighlighter ? _highlighterColor : _penColor;
  set color(int value) => _update(() {
        if (_isHighlighter) {
          _highlighterColor = value;
        } else {
          _penColor = value;
        }
      });

  int get widthIndex => _isHighlighter ? _highlighterWidthIndex : _penWidthIndex;
  set widthIndex(int value) => _update(() {
        if (_isHighlighter) {
          _highlighterWidthIndex = value;
        } else {
          _penWidthIndex = value;
        }
      });

  double get strokeWidth => widths[widthIndex];

  /// When off (the default), only the S Pen (and a mouse on desktop) draws.
  /// Fingers scroll the page instead, and a resting palm leaves no marks.
  bool _fingerDrawing = false;
  bool get fingerDrawing => _fingerDrawing;
  set fingerDrawing(bool value) => _update(() => _fingerDrawing = value);

  Set<PointerDeviceKind> get drawingDevices => {
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.mouse,
        if (_fingerDrawing) PointerDeviceKind.touch,
      };

  void _update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

class HandwritingToolbar extends StatelessWidget {
  const HandwritingToolbar({
    super.key,
    required this.controller,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    this.trailingPadding = 0,
  });

  final HandwritingToolController controller;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onClear;

  /// Space kept free on the right (for the mobile "..." block button).
  final double trailingPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEraser = controller.tool == HandwritingTool.eraser;
    final divider = SizedBox(
      height: 24,
      child: VerticalDivider(width: 16, color: theme.dividerColor),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: 4, right: trailingPadding),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.edit,
              tooltip: LocaleKeys.document_plugins_handwriting_pen.tr(),
              selected: controller.tool == HandwritingTool.pen,
              onPressed: () => controller.tool = HandwritingTool.pen,
            ),
            _ToolButton(
              icon: Icons.border_color,
              tooltip: LocaleKeys.document_plugins_handwriting_highlighter.tr(),
              selected: controller.tool == HandwritingTool.highlighter,
              onPressed: () => controller.tool = HandwritingTool.highlighter,
            ),
            _ToolButton(
              icon: Icons.cleaning_services_outlined,
              tooltip: LocaleKeys.document_plugins_handwriting_eraser.tr(),
              selected: isEraser,
              onPressed: () => controller.tool = HandwritingTool.eraser,
            ),
            if (!isEraser) ...[
              divider,
              for (final color in controller.colors)
                _ColorDot(
                  color: color == kHandwritingAutoColor
                      ? theme.colorScheme.onSurface
                      : Color(color),
                  selected: controller.color == color,
                  onTap: () => controller.color = color,
                ),
              divider,
              for (var i = 0; i < controller.widths.length; i++)
                _WidthDot(
                  size: 4.0 + i * 4,
                  selected: controller.widthIndex == i,
                  onTap: () => controller.widthIndex = i,
                ),
            ],
            divider,
            _ToolButton(
              icon: Icons.undo,
              tooltip: LocaleKeys.document_plugins_handwriting_undo.tr(),
              onPressed: canUndo ? onUndo : null,
            ),
            _ToolButton(
              icon: Icons.redo,
              tooltip: LocaleKeys.document_plugins_handwriting_redo.tr(),
              onPressed: canRedo ? onRedo : null,
            ),
            _ToolButton(
              icon: Icons.delete_outline,
              tooltip: LocaleKeys.document_plugins_handwriting_clear.tr(),
              onPressed: onClear,
            ),
            divider,
            _ToolButton(
              icon: Icons.touch_app_outlined,
              tooltip:
                  LocaleKeys.document_plugins_handwriting_fingerDrawing.tr(),
              selected: controller.fingerDrawing,
              onPressed: () =>
                  controller.fingerDrawing = !controller.fingerDrawing,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Selection is drawn explicitly: IconButton.isSelected only has an
    // effect under Material 3, which the app theme doesn't use.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        color: selected ? scheme.primary : scheme.onSurface,
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _WidthDot extends StatelessWidget {
  const _WidthDot({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
        ),
        alignment: Alignment.center,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.onSurface,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
