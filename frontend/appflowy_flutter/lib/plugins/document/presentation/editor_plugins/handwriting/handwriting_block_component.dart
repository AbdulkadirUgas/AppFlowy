import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'handwriting_stroke.dart';
import 'handwriting_toolbar.dart';

class HandwritingBlockKeys {
  const HandwritingBlockKeys._();

  static const String type = 'handwriting';

  /// The strokes, as a list of [HandwritingStroke.toJson] maps.
  static const String strokes = 'strokes';

  /// Canvas height in reference units (see [kHandwritingReferenceWidth]).
  static const String height = 'height';
}

const double _kDefaultHeight = 450;
const double _kMinHeight = 150;
const double _kMaxHeight = 20000;

/// How much the canvas grows when you write near its bottom edge.
const double _kAutoGrowStep = 300;

Node handwritingNode() => Node(
      type: HandwritingBlockKeys.type,
      attributes: {
        HandwritingBlockKeys.strokes: <Object>[],
        HandwritingBlockKeys.height: _kDefaultHeight,
      },
    );

class HandwritingBlockComponentBuilder extends BlockComponentBuilder {
  HandwritingBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return HandwritingBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class HandwritingBlockComponentWidget extends BlockComponentStatefulWidget {
  const HandwritingBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<HandwritingBlockComponentWidget> createState() =>
      _HandwritingBlockComponentWidgetState();
}

class _HandwritingBlockComponentWidgetState
    extends State<HandwritingBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final EditorState editorState = context.read<EditorState>();

  /// Tool settings are shared by every handwriting block, like a real pen.
  HandwritingToolController get tools => HandwritingToolController.instance;

  // Cached parse of the node's strokes, refreshed when the attribute changes.
  Object? _parsedFrom;
  List<HandwritingStroke> _strokes = const [];

  List<HandwritingStroke> get strokes {
    final raw = node.attributes[HandwritingBlockKeys.strokes];
    if (!identical(raw, _parsedFrom)) {
      _parsedFrom = raw;
      _strokes = HandwritingStroke.listFromJson(raw);
    }
    return _strokes;
  }

  double get _savedHeight {
    final value = node.attributes[HandwritingBlockKeys.height];
    return value is num
        ? value.toDouble().clamp(_kMinHeight, _kMaxHeight)
        : _kDefaultHeight;
  }

  /// Height while the resize handle is being dragged.
  double? _resizingHeight;
  double get height => _resizingHeight ?? _savedHeight;

  // Drawing state.
  int? _activePointer;
  HandwritingStrokeBuilder? _activeStroke;
  bool _erasing = false;
  final Set<int> _erasedIndexes = {};
  final ValueNotifier<int> _activeStrokeTick = ValueNotifier(0);

  /// Earlier versions of the strokes in this session, for undo and redo.
  /// Strokes are immutable, so each entry only copies the list itself.
  final List<List<HandwritingStroke>> _undoStack = [];
  final List<List<HandwritingStroke>> _redoStack = [];
  static const int _maxHistory = 100;

  @override
  void initState() {
    super.initState();
    tools.addListener(_onToolsChanged);
  }

  @override
  void dispose() {
    tools.removeListener(_onToolsChanged);
    _activeStrokeTick.dispose();
    super.dispose();
  }

  void _onToolsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: editorState.editableNotifier,
      builder: (context, editable, _) => _buildBlock(context, editable),
    );
  }

  Widget _buildBlock(BuildContext context, bool editable) {
    final theme = Theme.of(context);
    Widget child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable)
          HandwritingToolbar(
            controller: tools,
            canUndo: _undoStack.isNotEmpty,
            canRedo: _redoStack.isNotEmpty,
            onUndo: _undo,
            onRedo: _redo,
            onClear: strokes.isEmpty ? null : _confirmClear,
            trailingPadding: UniversalPlatform.isMobile ? 40 : 0,
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildCanvas(context, constraints.maxWidth, editable),
            ),
          ),
        ),
        if (editable) _buildResizeHandle(context),
      ],
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (UniversalPlatform.isMobile && editable) {
      child = MobileBlockActionButtons(
        node: node,
        editorState: editorState,
        child: child,
      );
    }

    return Padding(padding: padding, child: child);
  }

  Widget _buildCanvas(BuildContext context, double width, bool editable) {
    final scale = width / kHandwritingReferenceWidth;
    final autoColor = Theme.of(context).colorScheme.onSurface;
    final currentStrokes = strokes;

    Widget canvas = SizedBox(
      width: width,
      height: height * scale,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (currentStrokes.isEmpty && _activeStroke == null && editable)
            _buildPlaceholder(context),
          RepaintBoundary(
            child: CustomPaint(
              painter: HandwritingStrokesCustomPainter(
                strokes: currentStrokes,
                scale: scale,
                autoColor: autoColor,
                hidden: Set.of(_erasedIndexes),
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: HandwritingActiveStrokePainter(
                builder: () => _activeStroke,
                scale: scale,
                autoColor: autoColor,
                repaint: _activeStrokeTick,
              ),
            ),
          ),
        ],
      ),
    );

    if (!editable) {
      return canvas;
    }

    // Claim pen (and, when enabled, finger) pointers immediately so the page
    // doesn't scroll and the editor doesn't start a text selection while
    // writing. Fingers still scroll the page when finger drawing is off,
    // which also gives palm rejection while using the S Pen.
    final devices = tools.drawingDevices;
    canvas = RawGestureDetector(
      key: ValueKey(devices.length),
      behavior: HitTestBehavior.opaque,
      gestures: {
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(
            supportedDevices: devices,
            // Accept the S Pen while its side button is held (eraser).
            allowedButtonsFilter: (_) => true,
          ),
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _onPointerDown(event, scale),
        onPointerMove: (event) => _onPointerMove(event, scale),
        onPointerUp: (_) => _onPointerEnd(),
        onPointerCancel: (_) => _onPointerCancel(),
        child: canvas,
      ),
    );

    return MouseRegion(
      cursor: tools.tool == HandwritingTool.eraser
          ? SystemMouseCursors.cell
          : SystemMouseCursors.precise,
      child: canvas,
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Text(
          tools.fingerDrawing
              ? LocaleKeys.document_plugins_handwriting_fingerPlaceholder.tr()
              : LocaleKeys.document_plugins_handwriting_placeholder.tr(),
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }

  Widget _buildResizeHandle(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          final scale = box.size.width / kHandwritingReferenceWidth;
          setState(() {
            _resizingHeight = (height + details.delta.dy / scale)
                .clamp(_kMinHeight, _kMaxHeight);
          });
        },
        onVerticalDragEnd: (_) {
          final newHeight = _resizingHeight;
          _resizingHeight = null;
          if (newHeight != null) {
            _saveHeight(newHeight);
          }
        },
        child: SizedBox(
          height: 20,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pointer handling

  bool _accepts(PointerEvent event) =>
      tools.drawingDevices.contains(event.kind);

  /// The eraser end of a stylus, or the S Pen with its side button held,
  /// erases regardless of the selected tool.
  bool _wantsEraser(PointerEvent event) =>
      tools.tool == HandwritingTool.eraser ||
      event.kind == PointerDeviceKind.invertedStylus ||
      (event.kind == PointerDeviceKind.stylus &&
          event.buttons & kPrimaryStylusButton != 0);

  double _pressure(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return 0.5;
    }
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0) {
      return 0.5;
    }
    return ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _onPointerDown(PointerDownEvent event, double scale) {
    if (_activePointer != null || !_accepts(event)) {
      return;
    }
    _activePointer = event.pointer;
    if (_wantsEraser(event)) {
      _erasing = true;
      _eraseAt(event.localPosition, scale);
    } else {
      _erasing = false;
      _activeStroke = HandwritingStrokeBuilder(
        tool: tools.tool == HandwritingTool.highlighter
            ? HandwritingTool.highlighter
            : HandwritingTool.pen,
        color: tools.color,
        width: tools.strokeWidth,
      )..add(
          event.localPosition.dx / scale,
          event.localPosition.dy / scale,
          _pressure(event),
        );
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event, double scale) {
    if (event.pointer != _activePointer) {
      return;
    }
    if (_erasing) {
      _eraseAt(event.localPosition, scale);
      return;
    }
    final stroke = _activeStroke;
    if (stroke == null) {
      return;
    }
    stroke.add(
      event.localPosition.dx / scale,
      event.localPosition.dy / scale,
      _pressure(event),
    );
    _activeStrokeTick.value++;
  }

  void _onPointerEnd() {
    _activePointer = null;
    if (_erasing) {
      _erasing = false;
      _commitErase();
      return;
    }
    final stroke = _activeStroke;
    _activeStroke = null;
    if (stroke == null || stroke.isEmpty) {
      setState(() {});
      return;
    }
    _addStroke(stroke.build());
  }

  void _onPointerCancel() {
    _activePointer = null;
    _erasing = false;
    _erasedIndexes.clear();
    _activeStroke = null;
    setState(() {});
  }

  void _eraseAt(Offset position, double scale) {
    final x = position.dx / scale;
    final y = position.dy / scale;
    const radius = 12.0;
    final current = strokes;
    var changed = false;
    for (var i = 0; i < current.length; i++) {
      if (!_erasedIndexes.contains(i) && current[i].hitTest(x, y, radius)) {
        _erasedIndexes.add(i);
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Saving

  Future<void> _saveStrokes(
    List<HandwritingStroke> newStrokes, {
    double? newHeight,
  }) async {
    final transaction = editorState.transaction
      ..updateNode(node, {
        HandwritingBlockKeys.strokes:
            newStrokes.map((s) => s.toJson()).toList(),
        if (newHeight != null) HandwritingBlockKeys.height: newHeight,
      });
    await editorState.apply(transaction, withUpdateSelection: false);
    if (mounted) {
      setState(() {});
    }
  }

  void _addStroke(HandwritingStroke stroke) {
    // Grow the page when writing near the bottom, like an endless notebook.
    double? newHeight;
    var bottom = 0.0;
    for (var i = 1; i < stroke.points.length; i += 3) {
      if (stroke.points[i] > bottom) {
        bottom = stroke.points[i];
      }
    }
    if (bottom > height - _kAutoGrowStep / 3) {
      newHeight = (height + _kAutoGrowStep).clamp(_kMinHeight, _kMaxHeight);
    }
    _recordHistory();
    _saveStrokes([...strokes, stroke], newHeight: newHeight);
  }

  void _commitErase() {
    if (_erasedIndexes.isEmpty) {
      return;
    }
    final current = strokes;
    final remaining = [
      for (var i = 0; i < current.length; i++)
        if (!_erasedIndexes.contains(i)) current[i],
    ];
    _erasedIndexes.clear();
    _recordHistory();
    _saveStrokes(remaining);
  }

  void _saveHeight(double newHeight) {
    final transaction = editorState.transaction
      ..updateNode(node, {HandwritingBlockKeys.height: newHeight});
    editorState.apply(transaction, withUpdateSelection: false);
    setState(() {});
  }

  /// Remembers the current strokes before a drawing, erasing or clearing
  /// action changes them.
  void _recordHistory() {
    _undoStack.add(strokes);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(strokes);
    _saveStrokes(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(strokes);
    _saveStrokes(_redoStack.removeLast());
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LocaleKeys.document_plugins_handwriting_clear.tr()),
        content: Text(
          LocaleKeys.document_plugins_cover_alertDialogConfirmation.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(LocaleKeys.button_confirm.tr()),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _recordHistory();
      await _saveStrokes(const []);
    }
  }
}
