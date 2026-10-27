import 'package:flutter/material.dart';

/// The one way to open a bottom sheet.
///
/// A plain `showModalBottomSheet(isScrollControlled: true)` lets the sheet
/// grow to the full height of the screen and paint under the status bar. This
/// keeps the sheet below it, caps its height, and gives every sheet the same
/// drag handle.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: true,
  showDragHandle: showDragHandle,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.9,
  ),
  builder: builder,
);
