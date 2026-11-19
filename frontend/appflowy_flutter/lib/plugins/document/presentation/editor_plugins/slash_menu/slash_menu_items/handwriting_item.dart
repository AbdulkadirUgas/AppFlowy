import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';

import 'slash_menu_item_builder.dart';

final _keywords = [
  'handwriting',
  'pen',
  's pen',
  'stylus',
  'draw',
  'drawing',
  'sketch',
  'ink',
  'note',
];

SelectionMenuItem handwritingSlashMenuItem = SelectionMenuItem.node(
  getName: () => LocaleKeys.document_slashMenu_name_handwriting.tr(),
  keywords: _keywords,
  nodeBuilder: (editorState, _) => handwritingNode(),
  replace: (_, node) => node.delta?.isEmpty ?? false,
  nameBuilder: slashMenuItemNameBuilder,
  iconBuilder: (editorState, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.edit_s,
    isSelected: isSelected,
    style: style,
  ),
);
