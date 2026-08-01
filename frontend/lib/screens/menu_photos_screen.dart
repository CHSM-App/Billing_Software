import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../api.dart';
import '../l10n/l10n_ext.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Owner-only screen for managing dish photos shown to customers on the QR
/// order menu. This is the ONLY place the owner works with item images — the
/// billing and item-management screens never load or show photos.
///
/// Each photo is picked from the camera/gallery, resized and JPEG-compressed on
/// the device (so uploads stay small), then sent to the server which stores it
/// on disk and records its URL in items.image_url.
class MenuPhotosScreen extends ConsumerStatefulWidget {
  const MenuPhotosScreen({super.key});

  @override
  ConsumerState<MenuPhotosScreen> createState() => _MenuPhotosScreenState();
}

class _MenuPhotosScreenState extends ConsumerState<MenuPhotosScreen> {
  final _picker = ImagePicker();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  // Item ids currently uploading/removing — disables the card meanwhile.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await getItemsWithImages();
      if (!mounted) return;
      setState(() {
        _items = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return _items;
    return _items.where((i) {
      final name = '${i['name'] ?? ''}'.toLowerCase();
      final cat = '${i['category'] ?? ''}'.toLowerCase();
      return name.contains(q) || cat.contains(q);
    }).toList();
  }

  /// Full URL for a stored image_url. The server returns a root-relative path
  /// like `/uploads/items/ITEM.jpg?v=123`; prefix it with the API host (baseUrl
  /// without its trailing `/api`) so Image.network can load it.
  String _imageUrl(String relative) {
    var host = baseUrl;
    if (host.endsWith('/api')) host = host.substring(0, host.length - 4);
    return '$host$relative';
  }

  Future<void> _pickAndUpload(Map<String, dynamic> item, ImageSource src) async {
    final id = item['id'] as String;
    // Capture the localized error text before any await so we don't touch
    // BuildContext across async gaps.
    final failMsg = context.l10n.menuPhotosUploadFailed;
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: src,
        // A first-pass downscale by the picker; we still re-encode below to
        // guarantee JPEG + consistent compression across platforms.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
    } catch (e) {
      if (mounted) _snack(failMsg);
      return;
    }
    if (picked == null) return; // user cancelled

    setState(() => _busy.add(id));
    try {
      final raw = await picked.readAsBytes();
      final jpeg = await _compressToJpeg(raw);
      final newUrl = await uploadItemImage(id, jpeg);
      if (!mounted) return;
      setState(() => item['image_url'] = newUrl);
    } catch (e) {
      if (mounted) _snack(failMsg);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Decode, resize to max 1000px on the long edge, and JPEG-encode at ~80%.
  /// Runs the CPU-heavy encode work in a background isolate (compute) so the UI
  /// stays smooth. Keeps uploads to roughly a few hundred KB.
  Future<Uint8List> _compressToJpeg(Uint8List bytes) {
    return compute(_compressJpegSync, bytes);
  }

  Future<void> _removePhoto(Map<String, dynamic> item) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.menuPhotosRemove),
        content: Text(l10n.menuPhotosRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.menuPhotosRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final id = item['id'] as String;
    setState(() => _busy.add(id));
    try {
      await deleteItemImage(id);
      if (!mounted) return;
      setState(() => item['image_url'] = null);
    } catch (e) {
      if (mounted) _snack(l10n.menuPhotosRemoveFailed);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _showPickSheet(Map<String, dynamic> item) {
    final l10n = context.l10n;
    final hasPhoto = item['image_url'] != null;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.menuPhotosPickCamera),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(item, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.menuPhotosPickGallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(item, ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: Text(l10n.menuPhotosRemove,
                    style: const TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto(item);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuPhotosTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.space16, AppSpacing.space12, AppSpacing.space16, 0),
            child: Text(
              l10n.menuPhotosSubtitle,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.menuPhotosSearch,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
          ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 100),
        Center(child: Text(_error!, textAlign: TextAlign.center)),
      ]);
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Stack(children: [
        ListView(),
        EmptyState(
          icon: Icons.image_outlined,
          message: l10n.menuPhotosEmpty,
        ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.space12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: AppSpacing.space12,
          crossAxisSpacing: AppSpacing.space12,
          childAspectRatio: 0.82,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _photoCard(items[i], l10n),
      ),
    );
  }

  Widget _photoCard(Map<String, dynamic> item, AppLocalizations l10n) {
    final id = item['id'] as String;
    final url = item['image_url'] as String?;
    final busy = _busy.contains(id);

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: busy ? null : () => _showPickSheet(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.medium)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    Image.network(
                      _imageUrl(url),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  else
                    _placeholder(),
                  if (busy)
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      url != null ? Icons.edit_outlined : Icons.add_a_photo_outlined,
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      url != null ? l10n.menuPhotosChange : l10n.menuPhotosAdd,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.restaurant_menu,
              size: 34, color: AppColors.textDisabled),
        ),
      );
}

/// Top-level so it can run in a background isolate via [compute]. Decodes the
/// image, downscales the long edge to 1000px (only if larger), and re-encodes
/// as JPEG at quality 80.
Uint8List _compressJpegSync(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes; // not decodable — send as-is, server validates
  const maxEdge = 1000;
  img.Image out = decoded;
  final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (longEdge > maxEdge) {
    if (decoded.width >= decoded.height) {
      out = img.copyResize(decoded, width: maxEdge);
    } else {
      out = img.copyResize(decoded, height: maxEdge);
    }
  }
  return img.encodeJpg(out, quality: 80);
}
