import 'package:flutter/material.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// One label+value row in a [WarrantyExtraFieldsEditor] — either filled from
/// a category's [WarrantyFieldTemplate] (its label stays read-only, via
/// [templateKey]) or added ad-hoc by staff on the spot.
class WarrantyExtraRow {
  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;
  final String? templateKey;

  WarrantyExtraRow({required this.labelCtrl, required this.valueCtrl, this.templateKey});

  factory WarrantyExtraRow.fromField(WarrantyExtraField e) => WarrantyExtraRow(
        labelCtrl: TextEditingController(text: e.label),
        valueCtrl: TextEditingController(text: e.value),
      );

  void dispose() {
    labelCtrl.dispose();
    valueCtrl.dispose();
  }
}

/// Appends a row for every field of [category]'s template not already
/// present in [rows] (by [WarrantyExtraRow.templateKey]) — so re-applying a
/// template (e.g. after picking a different item of the same category)
/// never wipes a value staff already typed for a field the two share.
/// Mutates [rows] in place; returns true when anything was added, so the
/// caller knows whether a `setState` is actually needed.
bool applyWarrantyFieldTemplate(
  List<WarrantyExtraRow> rows,
  String? category,
  Map<String, WarrantyFieldTemplate>? templates,
) {
  if (category == null || category.trim().isEmpty) return false;
  final template = templates?[category];
  if (template == null) return false;
  final existingKeys = rows.map((r) => r.templateKey).toSet();
  var added = false;
  for (final f in template.fields) {
    if (existingKeys.contains(f.key)) continue;
    rows.add(WarrantyExtraRow(
      labelCtrl: TextEditingController(text: f.label),
      valueCtrl: TextEditingController(),
      templateKey: f.key,
    ));
    added = true;
  }
  return added;
}

/// Turns [rows] into the `extra_data` shape the API expects, dropping any
/// row whose label was left blank.
List<Map<String, String>> warrantyRowsPayload(List<WarrantyExtraRow> rows) => [
      for (final r in rows)
        if (r.labelCtrl.text.trim().isNotEmpty)
          {'label': r.labelCtrl.text.trim(), 'value': r.valueCtrl.text.trim()},
    ];

/// The dynamic "category template + ad-hoc rows" editor shared by the
/// Warranty tab's add/edit form and the billing screen's "Warranty Details"
/// section — one label+value field pair per row, template rows read-only on
/// their label, plus an "add detail" action for anything ad-hoc.
///
/// Styled to match the cart panel's "Additional Charges" section exactly
/// (`home_screen.dart`'s `_buildCartPanel`): a small grey heading with the
/// add action inline on the same row, each row in a bordered card with a
/// compact remove button — rather than a free-floating title and a
/// full-width button, which read as disconnected from the rest of the form.
///
/// Stateless by design: [rows] is owned by the caller's State, which passes
/// [onAddRow]/[onRemoveRow] to mutate it and trigger its own `setState`.
class WarrantyExtraFieldsEditor extends StatelessWidget {
  final List<WarrantyExtraRow> rows;
  final VoidCallback onAddRow;
  final void Function(WarrantyExtraRow row) onRemoveRow;
  /// Optional heading above the rows — omit when the caller already labels
  /// this section itself (e.g. a collapsible section title).
  final String? title;

  const WarrantyExtraFieldsEditor({
    super.key,
    required this.rows,
    required this.onAddRow,
    required this.onRemoveRow,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddRow,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.warrantyAddDetail),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space8),
                ),
              ),
            ],
          ),
        for (final row in rows)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.space8),
            padding: const EdgeInsets.all(AppSpacing.space8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Row(children: [
              Expanded(
                flex: 2,
                child: AppTextField(
                  label: l10n.warrantyDetailLabel,
                  controller: row.labelCtrl,
                  enabled: row.templateKey == null,
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              Expanded(
                flex: 3,
                child: AppTextField(
                  label: l10n.warrantyDetailValue,
                  controller: row.valueCtrl,
                ),
              ),
              IconButton(
                tooltip: l10n.warrantyRemoveDetail,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close,
                    size: 18, color: AppColors.textSecondary),
                onPressed: () => onRemoveRow(row),
              ),
            ]),
          ),
        if (title == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddRow,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.warrantyAddDetail),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space8),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
