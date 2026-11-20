import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped whenever a bill carrying a warranty-eligible item is finalized
/// online, so the Warranty tab (kept alive in the shell's IndexedStack, not
/// rebuilt on tab switch) can refresh itself immediately instead of only on
/// a manual pull-to-refresh. A plain counter, not the warranty data itself —
/// the Warranty screen still owns its own paginated/filtered fetch; this is
/// only a "something changed, re-fetch" signal.
final warrantyRefreshSignalProvider = StateProvider<int>((ref) => 0);
