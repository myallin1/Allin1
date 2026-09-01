import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/cloudinary_upload_service.dart';

/// A universal image caching widget for the Allin1 Super App.
/// 
/// - Automatically appends Cloudinary transformation parameters (e.g., w_600) 
///   if [cacheWidth] is provided, saving delivery bandwidth.
/// - Stores images on device disk (Android/iOS) or browser cache (Web) 
///   so they load instantly on subsequent offline visits.
class CachedCloudImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? placeholder;
  final Widget? errorWidget;

  // ================================================================
  // Image.network-COMPATIBLE CALLBACKS  (Aug 17 2026)
  // ================================================================
  // Six call sites (banner_slider, car_wash_screen, construction_screen,
  // eseva_service_screen, erode_offers_section) pass `errorBuilder` /
  // `loadingBuilder` — the Image.network parameter names. They were
  // migrated from Image.network to CachedCloudImage without the
  // callbacks being adapted, so the customer build failed with
  // "No named parameter with the name 'errorBuilder'".
  //
  // Accepting both signatures here fixes every call site at once and
  // touches none of them, rather than rewriting six files to the
  // placeholder/errorWidget style. It also means any future
  // Image.network -> CachedCloudImage swap is drop-in.
  //
  // Precedence: errorWidget/placeholder (this widget's own API) win if
  // both are supplied, so existing callers keep their exact behaviour.
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)?
      loadingBuilder;

  const CachedCloudImage(
    this.imageUrl, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder,
    this.errorWidget,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildErrorWidget(context);
    }

    // Rewrite URL to fetch only the needed size (e.g., w_400 instead of 1080p).
    // This is crucial for bandwidth savings on lists.
    final optimizedUrl = CloudinaryUploadService.optimizedUrl(
      imageUrl,
      width: cacheWidth,
    );

    return CachedNetworkImage(
      imageUrl: optimizedUrl,
      width: width,
      height: height,
      fit: fit,
      // memCacheWidth helps decode the image at a smaller resolution in memory
      memCacheWidth: cacheWidth,
      placeholder: (context, url) => _buildPlaceholder(context),
      errorWidget: (context, url, error) => _buildErrorWidget(context, error),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (placeholder != null) return placeholder!;
    if (loadingBuilder != null) {
      // Image.network calls loadingBuilder with a null chunk event once
      // the image is READY. CachedNetworkImage's placeholder only runs
      // while it is still loading, so a non-null event is passed here —
      // otherwise every caller's `progress == null ? child : spinner`
      // check would flip the wrong way and show the loaded state
      // forever. Byte counts are unknown at this layer, which the
      // ImageChunkEvent contract already allows for.
      return loadingBuilder!(
        context,
        const SizedBox.shrink(),
        const ImageChunkEvent(
          cumulativeBytesLoaded: 0,
          expectedTotalBytes: null,
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      color: Colors.grey.withValues(alpha: 0.1),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, [Object? error]) {
    if (errorWidget != null) return errorWidget!;
    if (errorBuilder != null) {
      return errorBuilder!(context, error ?? 'image failed to load', null);
    }
    return Container(
      width: width,
      height: height,
      color: Colors.grey.withValues(alpha: 0.1),
      child: const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.grey),
      ),
    );
  }
}
