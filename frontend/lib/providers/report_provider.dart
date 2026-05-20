import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart' as api;

class ReportNotifier extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() async {
    return api.getTodayReport();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final reportProvider =
    AsyncNotifierProvider<ReportNotifier, Map<String, dynamic>>(
        ReportNotifier.new);
