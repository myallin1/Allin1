import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:erode_superapp/services/cloudinary_admin_service.dart';
import 'package:erode_superapp/services/cloudinary_orphan_scanner.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';

class AdminCloudinaryDashboardScreen extends StatefulWidget {
  const AdminCloudinaryDashboardScreen({super.key});

  @override
  State<AdminCloudinaryDashboardScreen> createState() => _AdminCloudinaryDashboardScreenState();
}

class _AdminCloudinaryDashboardScreenState extends State<AdminCloudinaryDashboardScreen> {
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);

  bool _isLoading = true;
  CloudinaryUsageInfo? _usage;
  List<CloudinaryResource> _resources = [];
  List<CloudinaryResource> _filteredResources = [];
  final Set<String> _selectedIds = {};
  bool _isDeleting = false;
  String _searchQuery = '';

  // NEW (Aug 18 2026 — orphaned-image detection, per Nizam: "unwanted ah
  // images ah delete pandrathu... admin ku freedom irukamari"). Null =
  // scan never run this session (unknown either way — cards render
  // with no unused badge, exactly like before this feature existed).
  // Populated only when admin explicitly taps "Scan for Unused" below —
  // this is a real one-time Firestore read across several collections,
  // so it must never run automatically.
  Set<String>? _referencedPublicIds;
  bool _isScanning = false;
  bool _showUnusedOnly = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
    });

    final service = CloudinaryAdminService();
    if (!service.isConfigured) {
      setState(() => _isLoading = false);
      return;
    }

    final usage = await service.getUsage();
    final resources = await service.getResources();

    if (mounted) {
      setState(() {
        _usage = usage;
        _resources = resources;
        _isLoading = false;
      });
      // Re-apply whatever search text / unused-only toggle was already
      // set, instead of resetting the view on every refresh.
      _applyFilters();
    }
  }

  // NEW (Aug 18 2026 — orphaned-image detection). Explicit, admin-tapped
  // scan only — see the field comment on _referencedPublicIds above for
  // why this can never be automatic on the Spark plan.
  Future<void> _scanForUnused() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan for Unused Images'),
        content: const Text(
          'This reads every hero, seller menu, custom hotel, offer and ad '
          'document once to check which Cloudinary images are still in '
          'use. It is a real Firestore read cost — only run this when you '
          'actually want to clean up, not routinely.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Scan Now'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isScanning = true);
    try {
      final referenced = await CloudinaryOrphanScanner().collectReferencedPublicIds();
      if (!mounted) return;
      setState(() {
        _referencedPublicIds = referenced;
        _isScanning = false;
      });
      final unusedCount = _resources
          .where((r) => !referenced.contains(r.publicId))
          .length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unusedCount == 0
                ? 'Scan complete — every image is still in use.'
                : 'Scan complete — $unusedCount image(s) look unused.',
          ),
          backgroundColor: unusedCount == 0 ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  bool _isOrphaned(CloudinaryResource res) {
    final referenced = _referencedPublicIds;
    if (referenced == null) return false; // scan not run — unknown, don't claim orphaned
    return !referenced.contains(res.publicId);
  }

  void _applyFilters() {
    var list = _resources;
    if (_searchQuery.isNotEmpty) {
      list = list.where((r) => r.publicId.toLowerCase().contains(_searchQuery)).toList();
    }
    if (_showUnusedOnly && _referencedPublicIds != null) {
      list = list.where(_isOrphaned).toList();
    }
    setState(() => _filteredResources = list);
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Images'),
        content: Text('Are you sure you want to permanently delete ${_selectedIds.length} image(s)? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    final success = await CloudinaryAdminService().deleteResources(_selectedIds.toList());

    setState(() => _isDeleting = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Images deleted successfully'), backgroundColor: Colors.green),
        );
      }
      _loadData(); // refresh list
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete some or all images'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final bool isConfigured = CloudinaryAdminService().isConfigured;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Cloudinary Dashboard',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _isDeleting ? null : _deleteSelected,
            ),
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _pink),
                  )
                : const Icon(Icons.travel_explore_rounded),
            tooltip: 'Scan for unused images',
            onPressed: _isScanning || _isLoading ? null : _scanForUnused,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: !isConfigured
          ? _buildNotConfiguredState()
          : _isLoading
              ? const Center(child: CircularProgressIndicator(color: _pink))
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildUsageSection()),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Media Library (${_filteredResources.length})',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: _text),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search by file name...',
                            prefixIcon: const Icon(Icons.search, color: _muted),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _muted.withValues(alpha: 0.3))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          onChanged: (val) {
                            _searchQuery = val.toLowerCase();
                            _applyFilters();
                          },
                        ),
                      ),
                    ),
                    if (_referencedPublicIds != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            activeColor: _pink,
                            title: Text(
                              'Show unused only',
                              style: GoogleFonts.outfit(fontSize: 13, color: _text, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${_resources.where(_isOrphaned).length} of ${_resources.length} images look unused',
                              style: GoogleFonts.outfit(fontSize: 11.5, color: _muted),
                            ),
                            value: _showUnusedOnly,
                            onChanged: (v) {
                              _showUnusedOnly = v;
                              _applyFilters();
                            },
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (_filteredResources.isEmpty)
                      const SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Text('No images found in Cloudinary.'),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.8,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final res = _filteredResources[index];
                              final isSelected = _selectedIds.contains(res.publicId);
                              return _buildResourceCard(res, isSelected);
                            },
                            childCount: _filteredResources.length,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
    );
  }

  Widget _buildUsageSection() {
    if (_usage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withOpacity(0.2)),
        boxShadow: const [
          BoxShadow(color: Color(0x12FF4FA3), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, color: _pink),
              const SizedBox(width: 8),
              Text('Storage Usage', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: _text)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _usage!.storageUsedBytes / _usage!.storageLimitBytes,
            backgroundColor: _pink.withValues(alpha: 0.1),
            color: _pink,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatBytes(_usage!.storageUsedBytes), style: GoogleFonts.outfit(fontWeight: FontWeight.w500, color: _text)),
              Text(_formatBytes(_usage!.storageLimitBytes), style: GoogleFonts.outfit(color: _muted)),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Icon(Icons.sync_alt, color: _pink),
              const SizedBox(width: 8),
              Text('Bandwidth Usage', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16, color: _text)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _usage!.bandwidthUsedBytes / _usage!.bandwidthLimitBytes,
            backgroundColor: Colors.blue.withValues(alpha: 0.1),
            color: Colors.blue,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatBytes(_usage!.bandwidthUsedBytes), style: GoogleFonts.outfit(fontWeight: FontWeight.w500, color: _text)),
              Text(_formatBytes(_usage!.bandwidthLimitBytes), style: GoogleFonts.outfit(color: _muted)),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('API Requests', style: GoogleFonts.outfit(color: _muted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('${_usage!.requestsUsed} / ${_usage!.requestsLimit}', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: _text)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Images', style: GoogleFonts.outfit(color: _muted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('${_usage!.resourcesUsed} / ${_usage!.resourcesLimit}', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: _text)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transformations', style: GoogleFonts.outfit(color: _muted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('${_usage!.derivativesUsed}', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: _text)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResourceCard(CloudinaryResource res, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIds.remove(res.publicId);
          } else {
            _selectedIds.add(res.publicId);
          }
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.red : Colors.transparent,
            width: 3,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedCloudImage(
                res.secureUrl,
                fit: BoxFit.cover,
                cacheWidth: 300, // optimization for dashboard thumbnails
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  color: Colors.black.withValues(alpha: 0.7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatBytes(res.bytes),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        res.format.toUpperCase(),
                        style: const TextStyle(color: Colors.white70, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
              // NEW (Aug 18 2026 — orphaned-image detection): only shown
              // after an explicit scan, and only for images that scan
              // found unreferenced by any known Firestore collection —
              // helps admin tell "safe to delete" from "still in use"
              // instead of deleting blind.
              if (_isOrphaned(res))
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'UNUSED',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              if (isSelected)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotConfiguredState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: _muted),
            const SizedBox(height: 24),
            Text(
              'API Credentials Required',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: _text),
            ),
            const SizedBox(height: 12),
            Text(
              'To view usage and delete images, you must add your Cloudinary API Key and API Secret in lib/services/cloudinary_admin_service.dart.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}
