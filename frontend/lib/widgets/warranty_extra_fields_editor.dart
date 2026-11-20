import 'package:flutter/material.dart';
import '../l10n/l10n_ext.dart';
import '../models/models.dart';
import '../storage.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

/// One label+value row in a [WarrantyExtraFieldsEditor] — either one of the
/// shop's default labels (read-only, via [templateKey]; see
/// [addDefaultDetailRows]) or added ad-hoc by staff on the spot.
class WarrantyExtraRow {
  final TextEditingController labelCtrl;
  final TextEditingController valueCtrl;
  final String? templateKey;
  /// Tracks focus on the ad-hoc label field so its suggestion dropdown only
  /// shows while the staff member is actually editing that row.
  final FocusNode labelFocus = FocusNode();

  WarrantyExtraRow({required this.labelCtrl, required this.valueCtrl, this.templateKey});

  factory WarrantyExtraRow.fromField(WarrantyExtraField e) => WarrantyExtraRow(
        labelCtrl: TextEditingController(text: e.label),
        valueCtrl: TextEditingController(text: e.value),
      );

  void dispose() {
    labelCtrl.dispose();
    valueCtrl.dispose();
    labelFocus.dispose();
  }
}

/// Appends a read-only-label row for each of the shop's default [labels]
/// (Billing Setup → `detail_labels`) not already in [rows], so re-applying
/// never wipes a value staff already typed. Mutates [rows] in place.
void addDefaultDetailRows(List<WarrantyExtraRow> rows, List<String> labels) {
  final existing = rows.map((r) => r.templateKey).toSet();
  for (final l in labels) {
    if (existing.contains(l)) continue;
    rows.add(WarrantyExtraRow(
      labelCtrl: TextEditingController(text: l),
      valueCtrl: TextEditingController(),
      templateKey: l,
    ));
  }
}

/// Turns [rows] into the `extra_data` shape the API expects, dropping any
/// row whose label or value was left blank — an unfilled default
/// "Vehicle No" must not print an empty line on every bill.
List<Map<String, String>> warrantyRowsPayload(List<WarrantyExtraRow> rows) => [
      for (final r in rows)
        if (r.labelCtrl.text.trim().isNotEmpty &&
            r.valueCtrl.text.trim().isNotEmpty)
          {'label': r.labelCtrl.text.trim(), 'value': r.valueCtrl.text.trim()},
    ];

/// The ad-hoc labels (not read from a template) typed into [rows] — used to
/// remember them as suggestions for next time via `rememberWarrantyLabels`.
List<String> adHocWarrantyLabels(List<WarrantyExtraRow> rows) => [
      for (final r in rows)
        if (r.templateKey == null && r.labelCtrl.text.trim().isNotEmpty)
          r.labelCtrl.text.trim(),
    ];

/// The dynamic "shop default labels + ad-hoc rows" editor shared by the
/// Warranty tab's add/edit form and the billing screen's "Warranty Details"
/// section — one label+value field pair per row, default rows read-only on
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
          if (row.templateKey != null)
            // A predefined field (from the category's warranty template):
            // shown as a single, plain field — same as Customer
            // Address/GSTIN above it — labeled with the template's own
            // field name instead of a separate disabled "Label" box.
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space8),
              child: AppTextField(
                label: row.labelCtrl.text,
                controller: row.valueCtrl,
              ),
            )
          else
            _AdHocRow(
              row: row,
              onRemove: () => onRemoveRow(row),
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

/// One ad-hoc (non-template) label+value row, in its own bordered card with
/// a remove button and a [WarrantyLabelField] for the label.
class _AdHocRow extends StatelessWidget {
  final WarrantyExtraRow row;
  final VoidCallback onRemove;

  const _AdHocRow({
    required this.row,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.space8),
      padding: const EdgeInsets.all(AppSpacing.space8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 2,
          child: WarrantyLabelField(
            label: l10n.warrantyDetailLabel,
            controller: row.labelCtrl,
            focusNode: row.labelFocus,
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
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

/// A label text field that offers previously-typed warranty/extra-detail
/// labels as a dropdown below the field while it's focused — the same
/// "suggestions under the field" pattern as the billing screen's customer
/// name/phone autocomplete, rather than a static field.
///
/// Used both for the ad-hoc label in [WarrantyExtraFieldsEditor] and for
/// naming a category's template fields in the Items screen's "Manage
/// warranty fields" editor, so a label typed once (e.g. "Vehicle") is
/// offered again in both places.
class WarrantyLabelField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;

  const WarrantyLabelField({
    super.key,
    required this.label,
    required this.controller,
    this.focusNode,
  });

  @override
  State<WarrantyLabelField> createState() => _WarrantyLabelFieldState();
}

class _WarrantyLabelFieldState extends State<WarrantyLabelField> {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  // Loaded fresh from storage on mount rather than threaded down from a
  // distant ancestor's state: this field can end up inside a modal bottom
  // sheet, which is a separate route from the screen that owns the ancestor
  // — that screen's setState never reaches in here, so loading locally is
  // the only way this reliably picks up labels saved moments earlier.
  List<String> _localSuggestions = const [];

  /// Locally-remembered ad-hoc labels, deduped case-insensitively.
  List<String> get _suggestions {
    final seen = <String>{};
    return [
      for (final s in _localSuggestions)
        if (seen.add(s.toLowerCase())) s,
    ];
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onChange);
    widget.controller.addListener(_onChange);
    getWarrantyLabelSuggestions().then((s) {
      if (mounted) setState(() => _localSuggestions = s);
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onChange);
    widget.controller.removeListener(_onChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onChange() => setState(() {});

  void _select(String suggestion) {
    widget.controller.text = suggestion;
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final typed = widget.controller.text.trim().toLowerCase();
    final matches = _focusNode.hasFocus
        ? _suggestions
            .where((s) => s.toLowerCase().contains(typed))
            // Already-typed exact match: nothing left to suggest.
            .where((s) => s.toLowerCase() != typed)
            .take(6)
            .toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          label: widget.label,
          controller: widget.controller,
          focusNode: _focusNode,
        ),
        if (matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 190),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadow.small,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: matches.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final suggestion = matches[i];
                return InkWell(
                  // onTapDown, not onTap: the field losing focus would
                  // otherwise dismiss this list before the tap completed.
                  onTapDown: (_) => _select(suggestion),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.history,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(suggestion,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
