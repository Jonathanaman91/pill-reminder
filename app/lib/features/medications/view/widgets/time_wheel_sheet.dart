import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/medication.dart';

/// Opens a bottom sheet with two scrolling wheels (hours and minutes), like a
/// phone's alarm clock. Returns the chosen time, or null if cancelled.
///
/// [daysMask] and [startDate] are only used for the "Rings in …" headline,
/// so it tells the truth for "some days" schedules and future start dates.
Future<ClockTime?> showTimeWheelSheet(
  BuildContext context, {
  required ClockTime initial,
  required int daysMask,
  required DateTime startDate,
  String confirmLabel = 'Add',
}) {
  return showModalBottomSheet<ClockTime>(
    context: context,
    // Taller than the default sheet limit (9/16 of the screen), so the
    // wheels and buttons are never cut off on shorter phones.
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _TimeWheelSheet(
      initial: initial,
      daysMask: daysMask,
      startDate: startDate,
      confirmLabel: confirmLabel,
    ),
  );
}

/// How long until [time] next rings, on a day allowed by [daysMask] and not
/// before [startDate]. Null if no day in the next week fits (no days picked).
Duration? untilNextRing(ClockTime time, int daysMask, DateTime startDate, DateTime now) {
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  // Looks up to a year ahead so a start date far in the future still works.
  for (var i = 0; i < 366; i++) {
    final day = DateTime(now.year, now.month, now.day + i);
    if (day.isBefore(start)) continue;
    if (!WeekDays.has(daysMask, day.weekday - 1)) continue;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (at.isAfter(now)) return at.difference(now);
  }
  return null;
}

/// "Rings in 1 h 20 min", "Rings in 1 day 3 h", "Rings in 45 min".
String ringsInLabel(Duration? wait) {
  if (wait == null) return 'Reminder time';
  // Round up, so 08:00 picked at 07:59:30 reads "in 1 min", not "in 0 min".
  final totalMinutes = (wait.inSeconds / 60).ceil();
  final days = totalMinutes ~/ (24 * 60);
  final hours = (totalMinutes % (24 * 60)) ~/ 60;
  final minutes = totalMinutes % 60;

  if (days > 0) {
    final dayPart = days == 1 ? '1 day' : '$days days';
    return hours == 0 ? 'Rings in $dayPart' : 'Rings in $dayPart $hours h';
  }
  if (hours > 0) return minutes == 0 ? 'Rings in $hours h' : 'Rings in $hours h $minutes min';
  return 'Rings in $minutes min';
}

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({
    required this.initial,
    required this.daysMask,
    required this.startDate,
    required this.confirmLabel,
  });

  final ClockTime initial;
  final int daysMask;
  final DateTime startDate;
  final String confirmLabel;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;

  ClockTime get _selected => ClockTime(_hour, _minute);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final headline = ringsInLabel(
        untilNextRing(_selected, widget.daysMask, widget.startDate, DateTime.now()));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              textAlign: TextAlign.center,
              style: text.titleLarge?.tabular,
            ),
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              height: _Wheel.height,
              child: Row(
                children: [
                  Expanded(
                    child: _Wheel(
                      label: 'Hour',
                      count: 24,
                      initial: widget.initial.hour,
                      onChanged: (h) => setState(() => _hour = h),
                    ),
                  ),
                  // The colon sits on the selected row, like a clock.
                  ExcludeSemantics(
                    child: Text(':', style: _Wheel.styleFor(0, text)),
                  ),
                  Expanded(
                    child: _Wheel(
                      label: 'Minute',
                      count: 60,
                      initial: widget.initial.minute,
                      onChanged: (m) => setState(() => _minute = m),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(widget.confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One endless wheel of two-digit numbers (00–23 or 00–59). The row in the
/// middle is the choice: large and dark; the rows around it shrink and fade.
class _Wheel extends StatefulWidget {
  const _Wheel({
    required this.label,
    required this.count,
    required this.initial,
    required this.onChanged,
  });

  final String label;
  final int count;
  final int initial;
  final ValueChanged<int> onChanged;

  static const itemExtent = 56.0;
  static const height = itemExtent * 5; // two rows above and below the choice

  /// Size and colour by distance from the middle row.
  static TextStyle? styleFor(int distance, TextTheme text) {
    final base = text.displaySmall?.tabular;
    return switch (distance) {
      0 => base?.copyWith(fontSize: 44, fontWeight: FontWeight.w600, color: AppColors.ink),
      1 => base?.copyWith(fontSize: 34, fontWeight: FontWeight.w500, color: AppColors.inkTertiary),
      _ => base?.copyWith(fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.divider),
    };
  }

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  // Starts far from 0 so the wheel can be spun backwards past 00 at once.
  late final _controller =
      FixedExtentScrollController(initialItem: widget.count * 100 + widget.initial);
  late int _selected = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _distance(int value) {
    final d = (value - _selected).abs();
    return d < widget.count - d ? d : widget.count - d; // wraps around: 59 is next to 00
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = _selected.toString().padLeft(2, '0');

    return Semantics(
      label: widget.label,
      value: value,
      // Screen readers can step the wheel with swipe up/down.
      increasedValue: ((_selected + 1) % widget.count).toString().padLeft(2, '0'),
      decreasedValue: ((_selected - 1 + widget.count) % widget.count).toString().padLeft(2, '0'),
      onIncrease: () => _controller.animateToItem(_controller.selectedItem + 1,
          duration: const Duration(milliseconds: 150), curve: Curves.easeOut),
      onDecrease: () => _controller.animateToItem(_controller.selectedItem - 1,
          duration: const Duration(milliseconds: 150), curve: Curves.easeOut),
      child: ExcludeSemantics(
        child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: _Wheel.itemExtent,
          diameterRatio: 1.8,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) {
            final next = index % widget.count;
            if (next == _selected) return;
            HapticFeedback.selectionClick();
            setState(() => _selected = next);
            widget.onChanged(next);
          },
          childDelegate: ListWheelChildLoopingListDelegate(
            children: [
              for (var i = 0; i < widget.count; i++)
                Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: _Wheel.styleFor(_distance(i), text) ?? const TextStyle(),
                    child: Text(i.toString().padLeft(2, '0')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
