// ================================================================
// Notifications Screen
// Allin1 Super App - Allin1
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/update_service.dart';

const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kOrange = Color(0xFFE07C6F);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  final Dio _dio = Dio();
  final Map<String, double> _downloadProgress = <String, double>{};
  final Set<String> _downloadingDocIds = <String>{};
  final Set<String> _installerOpenedDocIds = <String>{};
  final Map<String, String> _downloadErrors = <String, String>{};
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context, user?.uid),
            child: Text(
              'Mark all read',
              style: GoogleFonts.outfit(color: kGold),
            ),
          ),
        ],
      ),
      body: user == null
          ? Center(
              child: Text(
                'Please login',
                style: GoogleFonts.outfit(color: kMuted),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: kGold),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (ctx, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data()! as Map<String, dynamic>;
                    return _buildNotificationItem(context, data, doc.id);
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none, color: kMuted, size: 64),
          const SizedBox(height: 16),
          Text(
            'No notifications',
            style: GoogleFonts.outfit(color: kText, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            "You're all caught up!",
            style: GoogleFonts.outfit(color: kMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    Map<String, dynamic> data,
    String docId,
  ) {
    final type = data['type'] as String? ?? 'promo';
    final title = data['title'] as String? ?? '';
    final message = data['message'] as String? ?? '';
    final isRead = data['read'] as bool? ?? false;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final apkUrl = (data['apk_url'] as String?)?.trim() ?? '';
    final posterUrl = (data['poster_url'] as String?)?.trim() ?? '';
    final appVariant = (data['app_variant'] as String?)?.trim() ?? '';
    final versionName = (data['version_name'] as String?)?.trim() ?? '';
    final distribution = (data['distribution'] as String?)?.trim() ?? '';
    final featureList = ((data['feature_list'] as List?) ?? const <dynamic>[])
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final shorebirdStatus = (data['shorebird_status'] as String?)?.trim() ?? '';
    final currentPatch = (data['shorebird_current_patch'] as num?)?.toInt();
    final nextPatch = (data['shorebird_next_patch'] as num?)?.toInt();
    final binaryUpdateAvailable = data['binary_update_available'] == true;
    final effectiveApkUrl = apkUrl.isNotEmpty
        ? apkUrl
        : UpdateService().fallbackApkUrl(
            appVariant.isNotEmpty ? appVariant : 'customer',
          );
    final isUpdateNotification = data['update_available'] == true ||
        apkUrl.isNotEmpty ||
        posterUrl.isNotEmpty ||
        featureList.isNotEmpty ||
        shorebirdStatus.isNotEmpty;
    final isDownloading = _downloadingDocIds.contains(docId);
    final downloadProgress = _downloadProgress[docId] ?? 0;
    final downloadError = _downloadErrors[docId];
    final installerOpened = _installerOpenedDocIds.contains(docId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isRead ? kCard : kCard2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _markAsRead(context, docId),
          onLongPress: () => _showDeleteDialog(context, docId),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNotificationIcon(type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          color: kText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: GoogleFonts.outfit(
                          color: kMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (appVariant.isNotEmpty || versionName.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (appVariant.isNotEmpty)
                              _buildMetaChip(appVariant.toUpperCase()),
                            if (versionName.isNotEmpty)
                              _buildMetaChip('v$versionName'),
                          ],
                        ),
                      ],
                      if (createdAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _formatTime(createdAt),
                          style: GoogleFonts.outfit(
                            color: kMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (isUpdateNotification) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (posterUrl.isNotEmpty) ...[
                                _buildPoster(posterUrl),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                binaryUpdateAvailable
                                    ? 'APK update ready for download.'
                                    : 'Logic update available.',
                                style: GoogleFonts.outfit(
                                  color: kText,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                binaryUpdateAvailable
                                    ? 'Tap Update Now to download the APK and open the Android installer.'
                                    : 'This update can be delivered as a background Shorebird logic patch on next launch.',
                                style: GoogleFonts.outfit(
                                  color: kMuted,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                              if (featureList.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  "What's new",
                                  style: GoogleFonts.outfit(
                                    color: kText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...featureList.take(5).map(
                                      (feature) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(top: 4),
                                              child: Icon(
                                                Icons.check_circle_rounded,
                                                color: kGold,
                                                size: 14,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                feature,
                                                style: GoogleFonts.outfit(
                                                  color: kText,
                                                  fontSize: 11,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ],
                              if (distribution.isNotEmpty ||
                                  shorebirdStatus.isNotEmpty ||
                                  currentPatch != null ||
                                  nextPatch != null) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (distribution.isNotEmpty)
                                      _buildMetaChip(
                                        distribution
                                            .replaceAll('_', ' ')
                                            .toUpperCase(),
                                      ),
                                    if (shorebirdStatus.isNotEmpty)
                                      _buildMetaChip(
                                        'PATCH ${shorebirdStatus.toUpperCase()}',
                                      ),
                                    if (currentPatch != null)
                                      _buildMetaChip('LIVE P$currentPatch'),
                                    if (nextPatch != null &&
                                        nextPatch != currentPatch)
                                      _buildMetaChip('NEXT P$nextPatch'),
                                  ],
                                ),
                              ],
                              if (isDownloading) ...[
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: downloadProgress <= 0
                                      ? null
                                      : downloadProgress,
                                  minHeight: 8,
                                  color: kGold,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}% downloaded',
                                  style: GoogleFonts.outfit(
                                    color: kText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (downloadError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  downloadError,
                                  style: GoogleFonts.outfit(
                                    color: kRed,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (installerOpened) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Installer opened. Complete the update from Android.',
                                  style: GoogleFonts.outfit(
                                    color: kGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: AnimatedBuilder(
                                  animation: _glowController,
                                  builder: (context, _) {
                                    final glow =
                                        0.18 + (_glowController.value * 0.34);
                                    return DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                kGold.withValues(alpha: glow),
                                            blurRadius: 20,
                                            spreadRadius: 1.5,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton.icon(
                                        onPressed: isDownloading ||
                                                effectiveApkUrl.isEmpty
                                            ? null
                                            : () => _downloadAndInstallApk(
                                                  context,
                                                  docId: docId,
                                                  apkUrl: effectiveApkUrl,
                                                ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: kGold,
                                          foregroundColor: Colors.black,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        icon: Icon(
                                          installerOpened
                                              ? Icons.install_mobile_rounded
                                              : Icons.system_update_alt_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          installerOpened
                                              ? 'Reopen Installer'
                                              : binaryUpdateAvailable
                                                  ? 'Update Now'
                                                  : 'Waiting For Patch',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: kGold,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kGold.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: kGold,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildPoster(String posterUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPurple.withValues(alpha: 0.65),
                kGold.withValues(alpha: 0.30),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                posterUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  final total = progress.expectedTotalBytes;
                  final value = total == null || total == 0
                      ? null
                      : progress.cumulativeBytesLoaded / total;
                  return Center(
                    child: SizedBox(
                      width: 48,
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        color: kGold,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.white.withValues(alpha: 0.05),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          color: kGold.withValues(alpha: 0.95),
                          size: 34,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Poster preview unavailable',
                          style: GoogleFonts.outfit(
                            color: kText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: kGold,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Major app update available',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Poster highlights the latest features in this release.',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(String type) {
    IconData icon;
    Color color;

    switch (type) {
      case 'ride_accepted':
        icon = Icons.directions_bike;
        color = kGold;
        break;
      case 'ride_completed':
        icon = Icons.check_circle;
        color = kGreen;
        break;
      case 'order_accepted':
        icon = Icons.inventory_2;
        color = kPurple;
        break;
      case 'order_delivered':
        icon = Icons.rocket_launch;
        color = kGreen;
        break;
      case 'payment':
        icon = Icons.currency_rupee;
        color = kGold;
        break;
      case 'app_update':
        icon = Icons.system_update_alt_rounded;
        color = kGold;
        break;
      default:
        icon = Icons.celebration;
        color = kOrange;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _downloadAndInstallApk(
    BuildContext context, {
    required String docId,
    required String apkUrl,
  }) async {
    if (apkUrl.isEmpty) {
      return;
    }

    if (kIsWeb) {
      _showSnackBar(
        context,
        'In-app APK install is available on Android devices only.',
        isError: true,
      );
      return;
    }

    setState(() {
      _downloadingDocIds.add(docId);
      _downloadProgress[docId] = 0;
      _downloadErrors.remove(docId);
      _installerOpenedDocIds.remove(docId);
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}\\${_buildApkFileName(docId, apkUrl)}';

      await _dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (!mounted) {
            return;
          }
          final progress = total <= 0 ? 0.0 : received / total;
          setState(() {
            _downloadProgress[docId] = progress;
          });
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 1),
        ),
      );

      final result = await OpenFilex.open(filePath);
      if (!mounted) {
        return;
      }
      setState(() {
        _installerOpenedDocIds.add(docId);
      });
      await _markAsRead(context, docId);

      if (result.type != ResultType.done) {
        _showSnackBar(
          context,
          result.message.isNotEmpty
              ? result.message
              : 'Download finished, but Android could not open the installer.',
          isError: true,
        );
      } else {
        _showSnackBar(
          context,
          'APK downloaded. Android installer opened.',
        );
      }
    } on DioException catch (error) {
      final message = error.message?.trim().isNotEmpty ?? false
          ? error.message!.trim()
          : 'Download failed. Check your internet connection and try again.';
      if (mounted) {
        setState(() {
          _downloadErrors[docId] = message;
        });
      }
      _showSnackBar(context, message, isError: true);
    } catch (error) {
      final message = 'Unable to download or open the APK: $error';
      if (mounted) {
        setState(() {
          _downloadErrors[docId] = message;
        });
      }
      _showSnackBar(context, message, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _downloadingDocIds.remove(docId);
        });
      }
    }
  }

  String _buildApkFileName(String docId, String apkUrl) {
    final uri = Uri.tryParse(apkUrl);
    final lastSegment =
        uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final rawName = lastSegment.toLowerCase().endsWith('.apk')
        ? lastSegment
        : 'allin1_update_$docId.apk';
    return rawName.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        backgroundColor: isError ? kRed : kGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _markAsRead(BuildContext context, String docId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(docId)
        .update({'read': true});
  }

  Future<void> _markAllRead(BuildContext context, String? userId) async {
    if (userId == null) {
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'All notifications marked as read',
            style: GoogleFonts.notoSansTamil(color: Colors.white),
          ),
          backgroundColor: kGreen,
        ),
      );
    }
  }

  void _showDeleteDialog(BuildContext context, String docId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard2,
        title: Text('Delete?', style: GoogleFonts.outfit(color: kText)),
        content: Text(
          'Remove this notification?',
          style: GoogleFonts.outfit(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: kMuted)),
          ),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance
                  .collection('notifications')
                  .doc(docId)
                  .delete();
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: GoogleFonts.outfit(color: kRed)),
          ),
        ],
      ),
    );
  }
}
