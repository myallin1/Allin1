// ================================================================
// order_photo_gallery.dart — shared "order photo evidence" viewer
// ================================================================
// Renders the list of Cloudinary screenshot URLs a customer attached to
// an order (currently: grocery_order's DMart-cart-screenshot workflow,
// see grocery_order_screen.dart's `listImageUrls`) as a clean,
// corporate-look horizontal thumbnail strip, with a full-screen
// pinch-zoom viewer on tap. Shared by every surface that needs to show
// a hero/admin these photos so they read the same everywhere: the
// hero's accept dialog (hero_home_screen.dart), the admin escalation
// queue (admin_new_orders_screen.dart), and the admin per-type list
// (admin_service_requests_screen.dart).
import 'package:flutter/material.dart';

import '../services/cloudinary_upload_service.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';

/// Compact horizontal strip of thumbnails, tap any one to open the
/// full-screen viewer. Renders nothing if [imageUrls] is empty, so
/// callers can drop this in unconditionally.
class OrderPhotoGallery extends StatelessWidget {
  final List<String> imageUrls;
  final double thumbnailSize;
  final String? label;

  const OrderPhotoGallery({
    required this.imageUrls,
    this.thumbnailSize = 64,
    this.label,
    super.key,
  });

  void _openViewer(BuildContext context, int startIndex) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _OrderPhotoViewer(imageUrls: imageUrls, startIndex: startIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(
            children: [
              const Icon(Icons.photo_library_outlined, size: 15, color: Color(0xFF7777A0)),
              const SizedBox(width: 5),
              Text(
                label!,
                style: const TextStyle(color: Color(0xFF7777A0), fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: thumbnailSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => _openViewer(context, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedCloudImage(
                  // Thumbnails are the single worst bandwidth offender:
                  // without a width cap this slot downloads the full
                  // stored original just to render it at thumbnailSize.
                  // 2x for retina/high-DPI sharpness.
                  CloudinaryUploadService.optimizedUrl(
                    imageUrls[i],
                    width: (thumbnailSize * 2).round(),
                  ),
                  width: thumbnailSize,
                  height: thumbnailSize,
                  fit: BoxFit.cover,
                  placeholder: Container(
                    width: thumbnailSize,
                    height: thumbnailSize,
                    color: const Color(0xFF1A1A2E),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4FA3)),
                      ),
                    ),
                  ),
                  errorWidget: Container(
                    width: thumbnailSize,
                    height: thumbnailSize,
                    color: const Color(0xFF1A1A2E),
                    child: const Icon(Icons.broken_image_outlined, color: Color(0xFF7777A0), size: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen swipeable, pinch-zoomable viewer with a page counter and
/// close button — the standard "review evidence photos" pattern.
class _OrderPhotoViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int startIndex;
  const _OrderPhotoViewer({required this.imageUrls, required this.startIndex});

  @override
  State<_OrderPhotoViewer> createState() => _OrderPhotoViewerState();
}

class _OrderPhotoViewerState extends State<_OrderPhotoViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex;
    _controller = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedCloudImage(
                    // Full-screen viewer — no width cap (the user is
                    // zooming into detail here), but f_auto/q_auto still
                    // cut 30-50% via WebP/AVIF at identical quality.
                    CloudinaryUploadService.optimizedUrl(widget.imageUrls[i]),
                    fit: BoxFit.contain,
                    errorWidget:
                        const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.imageUrls.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reads `details['listImageUrls']` (new, multi-image field) with a
/// fallback to the older singular `details['listImageUrl']` so orders
/// placed before this feature shipped still show their one photo.
List<String> orderPhotoUrlsFromDetails(Map details) {
  final raw = details['listImageUrls'];
  if (raw is List) {
    return raw.whereType<String>().where((u) => u.isNotEmpty).toList();
  }
  final single = details['listImageUrl'] as String?;
  if (single != null && single.isNotEmpty) return [single];
  return const [];
}

