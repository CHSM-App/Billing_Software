import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Whether a GST filing period is a calendar month or a quarter.
enum GstPeriodType { monthly, quarterly }

/// A GST filing period — the month or quarter a return covers.
///
/// Shared by every GST report screen (GSTR-1, GSTR-2, GSTR-3B) so they all
/// agree on what "August 2026" or "Q3" means, and so the leap-year arithmetic
/// below exists exactly once.
class GstPeriod {
  final GstPeriodType type;
  final int year;

  /// 1-12 for monthly; 1-4 for quarterly.
  final int index;

  const GstPeriod(
      {required this.type, required this.year, required this.index});

  /// The period containing today.
  factory GstPeriod.current([GstPeriodType type = GstPeriodType.monthly]) {
    final now = DateTime.now();
    return GstPeriod(
      type: type,
      year: now.year,
      index: type == GstPeriodType.monthly
          ? now.month
          : ((now.month - 1) ~/ 3) + 1,
    );
  }

  /// Inclusive first day.
  DateTime get from => type == GstPeriodType.monthly
      ? DateTime(year, index, 1)
      : DateTime(year, (index - 1) * 3 + 1, 1);

  /// Inclusive last day. Day 0 of the following month is that month's last day,
  /// which handles February and leap years without a special case.
  DateTime get to => type == GstPeriodType.monthly
      ? DateTime(year, index + 1, 0)
      : DateTime(year, (index - 1) * 3 + 4, 0);

  String get label => type == GstPeriodType.monthly
      ? DateFormat('MMMM yyyy').format(from)
      : 'Q$index $year '
          '(${DateFormat('MMM').format(from)}–${DateFormat('MMM').format(to)})';

  /// Short form for filenames, e.g. 2026-08 or 2026-Q3.
  String get slug => type == GstPeriodType.monthly
      ? DateFormat('yyyy-MM').format(from)
      : '$year-Q$index';

  String get fromApi => DateFormat('yyyy-MM-dd').format(from);
  String get toApi => DateFormat('yyyy-MM-dd').format(to);

  /// Whether this period has already started (a future period has no data).
  bool get isPast {
    final now = DateTime.now();
    final currentStart = type == GstPeriodType.monthly
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
    return from.isBefore(currentStart);
  }

  GstPeriod shifted(int delta) {
    final max = type == GstPeriodType.monthly ? 12 : 4;
    var y = year;
    var i = index + delta;
    while (i < 1) {
      i += max;
      y--;
    }
    while (i > max) {
      i -= max;
      y++;
    }
    return GstPeriod(type: type, year: y, index: i);
  }

  /// Switching type re-anchors to the CURRENT month/quarter: a month index of
  /// 11 is meaningless as a quarter, so the index cannot simply carry over.
  GstPeriod withType(GstPeriodType t) => GstPeriod.current(t);
}

/// Monthly/quarterly toggle plus a ‹ label › stepper.
class GstPeriodSelector extends StatelessWidget {
  final GstPeriod period;
  final ValueChanged<GstPeriod> onChanged;

  const GstPeriodSelector(
      {super.key, required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<GstPeriodType>(
          segments: const [
            ButtonSegment(
                value: GstPeriodType.monthly, label: Text('Monthly')),
            ButtonSegment(
                value: GstPeriodType.quarterly, label: Text('Quarterly')),
          ],
          selected: {period.type},
          onSelectionChanged: (s) => onChanged(period.withType(s.first)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous period',
            onPressed: () => onChanged(period.shifted(-1)),
          ),
          Expanded(
            child: Text(
              period.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next period',
            // Never page into a period that has not started.
            onPressed: period.isPast ? () => onChanged(period.shifted(1)) : null,
          ),
        ]),
        Center(
          child: Text(
            '${DateFormat('dd MMM yyyy').format(period.from)} — '
            '${DateFormat('dd MMM yyyy').format(period.to)}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Card shell shared by the GST report screens.
class GstCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const GstCard(
      {super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadow.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Label/value row used throughout the GST reports.
class GstKv extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const GstKv(this.label, this.value,
      {super.key, this.bold = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  color: valueColor ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Horizontally scrollable table so a wide GST breakdown never overflows.
class GstTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;

  const GstTable({super.key, required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Nothing to show for this period.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 44,
        columnSpacing: 20,
        columns: [
          for (final h in headers)
            DataColumn(
                label: Text(h,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)))
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              for (final c in r)
                DataCell(Text(c, style: const TextStyle(fontSize: 12)))
            ])
        ],
      ),
    );
  }
}
