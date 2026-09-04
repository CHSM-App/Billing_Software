import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage.dart';
import 'items_provider.dart' show categoryTreeProvider;

/// The major-category chip strip's display order, as arranged by drag-and-drop
/// on THIS device. Persisted locally per business (see storage.dart) —
/// deliberately never synced to the server, so two staff on two phones are
/// each free to arrange the strip however suits them, and a fresh install
/// starts from the plain alphabetical default with nothing to configure.
///
/// Falls back to alphabetical — the order [categoryTreeProvider] already
/// produces — for a business that has never customised it, and for any major
/// this device has not seen saved before: a newly added major category is
/// appended at the end rather than vanishing from the strip or crashing.
class MajorCategoryOrderNotifier extends AsyncNotifier<List<String>> {
  // [reorder] updates `state` synchronously but persists to disk
  // asynchronously (see there). If something ELSE re-triggers [build] — e.g.
  // popping back to the Items screen, which invalidates categoryTreeProvider
  // in a few places — while that write is still in flight, build() would
  // otherwise re-derive the order from disk BEFORE the write lands, reading
  // the stale pre-drag value and silently overwriting the correct one. A drag
  // immediately followed by navigating away reproduced exactly that. Holding
  // the in-flight save here and awaiting it at the top of [build] closes the
  // race: a rebuild always sees the order it was just told to persist.
  Future<void>? _pendingSave;

  @override
  Future<List<String>> build() async {
    if (_pendingSave != null) await _pendingSave;
    final alphabetical = (await ref.watch(categoryTreeProvider.future))
        .keys
        .where((m) => m.isNotEmpty)
        .toList();
    return _applySavedOrder(alphabetical);
  }

  Future<List<String>> _applySavedOrder(List<String> alphabetical) async {
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty) return alphabetical;
    final raw = await getMajorCategoryOrder(businessId);
    if (raw == null) return alphabetical;

    List<dynamic> saved;
    try {
      saved = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      // Corrupt/foreign JSON — fall back rather than 500-ing the billing screen
      // over a local-storage preference.
      return alphabetical;
    }

    final known = alphabetical.toSet();
    // Saved majors, in their saved order, but only the ones that still exist —
    // a renamed or deleted major must not leave a stale/empty chip behind.
    final ordered = [
      for (final m in saved.map((e) => e.toString())) if (known.contains(m)) m,
    ];
    // Anything new since the order was last saved lands at the end. Filtering
    // `alphabetical` (already sorted) keeps that tail alphabetical too.
    final orderedSet = ordered.toSet();
    ordered.addAll(alphabetical.where((m) => !orderedSet.contains(m)));
    return ordered;
  }

  /// Persist a new explicit order — call after a drag-reorder completes.
  /// Updates state immediately: the whole point of dragging is seeing it stick.
  ///
  /// Deliberately NOT an `async` function itself: calling an async function
  /// runs its body synchronously up to the first await, so if [_persist]'s
  /// `await getBusinessId()` were the first suspension point INSIDE reorder,
  /// [_pendingSave] would stay null for however long that takes — wide enough
  /// on a real platform-channel round trip for a racing [build] to slip
  /// through unguarded. Splitting the write into [_persist] and assigning
  /// [_pendingSave] here, synchronously, closes that gap: the field is set
  /// the INSTANT reorder() is called, before this function returns at all.
  Future<void> reorder(List<String> newOrder) {
    state = AsyncData(newOrder);
    late final Future<void> save;
    save = _persist(newOrder).whenComplete(() {
      // Only clear if a NEWER reorder hasn't already replaced this entry.
      if (identical(_pendingSave, save)) _pendingSave = null;
    });
    _pendingSave = save;
    return save;
  }

  Future<void> _persist(List<String> newOrder) async {
    final businessId = await getBusinessId();
    if (businessId == null || businessId.isEmpty) return;
    await saveMajorCategoryOrder(businessId, jsonEncode(newOrder));
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final majorCategoryOrderProvider =
    AsyncNotifierProvider<MajorCategoryOrderNotifier, List<String>>(
        MajorCategoryOrderNotifier.new);
