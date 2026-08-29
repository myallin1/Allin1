// ================================================================
// Credentials Screen - Credential List
// Allin1 Super App - Allin1
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/credential.dart';
import '../models/credential_category.dart';
import 'credential_detail_screen.dart';

const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCategoryId;
  List<Credential> _credentials = [];
  List<CredentialCategory> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadCredentials(),
        _loadCategories(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCredentials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('credentials')
          .where('userId', isEqualTo: user.uid)
          .where('isDeleted', isEqualTo: false)
          .orderBy('updatedAt', descending: true)
          .get();

      final credentials =
          snapshot.docs.map((doc) => Credential.fromJson(doc.data())).toList();

      if (mounted) {
        setState(() => _credentials = credentials);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error loading credentials: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _loadCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('credentialCategories')
          .where('userId', isEqualTo: user.uid)
          .orderBy('sortOrder')
          .get();

      final categories = snapshot.docs
          .map((doc) => CredentialCategory.fromJson(doc.data()))
          .toList();

      if (mounted) {
        setState(() => _categories = categories);
      }
    } catch (e) {
      // Silently fail - categories are optional
    }
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  List<Credential> get _filteredCredentials {
    var filtered = _credentials;

    // Filter by category
    if (_selectedCategoryId != null) {
      filtered =
          filtered.where((c) => c.categoryId == _selectedCategoryId).toList();
    }

    // Filter by search
    final query = _searchController.text.toLowerCase().trim();
    if (query.isNotEmpty) {
      filtered =
          filtered.where((c) => c.title.toLowerCase().contains(query)).toList();
    }

    return filtered;
  }

  CredentialCategory? _getCategory(String? categoryId) {
    if (categoryId == null) {
      return null;
    }
    try {
      return _categories.firstWhere((c) => c.id == categoryId);
    } catch (_) {
      return null;
    }
  }

  IconData _getTypeIcon(CredentialType type) {
    switch (type) {
      case CredentialType.password:
        return Icons.lock_outline;
      case CredentialType.apiKey:
        return Icons.key;
      case CredentialType.secureNote:
        return Icons.note_outlined;
      case CredentialType.bankAccount:
        return Icons.account_balance_outlined;
      case CredentialType.wifi:
        return Icons.wifi;
      case CredentialType.card:
        return Icons.credit_card_outlined;
      case CredentialType.other:
        return Icons.folder_outlined;
    }
  }

  Color _getTypeColor(CredentialType type) {
    switch (type) {
      case CredentialType.password:
        return kPurple;
      case CredentialType.apiKey:
        return kGreen;
      case CredentialType.secureNote:
        return kGold;
      case CredentialType.bankAccount:
        return const Color(0xFF4CAF50);
      case CredentialType.wifi:
        return const Color(0xFF00BCD4);
      case CredentialType.card:
        return const Color(0xFFE91E63);
      case CredentialType.other:
        return kMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          'My Credentials',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: kText,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: kGold),
            onPressed: _navigateToDetail,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: kPurple),
            )
          : Column(
              children: [
                _buildSearchBar(),
                _buildCategoryChips(),
                Expanded(child: _buildCredentialsList()),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.outfit(color: kText),
        decoration: InputDecoration(
          hintText: 'Search credentials...',
          hintStyle: GoogleFonts.outfit(color: kMuted),
          prefixIcon: const Icon(Icons.search, color: kMuted),
          filled: true,
          fillColor: kCard2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPurple),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildCategoryChip(null, 'All', Icons.all_inclusive),
          ..._categories.map(
            (category) => _buildCategoryChip(
              category.id,
              category.name,
              _getCategoryIcon(category.icon),
              color: _parseColor(category.color),
            ),
          ),
          _buildAddCategoryChip(),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(
    String? id,
    String label,
    IconData icon, {
    Color? color,
  }) {
    final isSelected = _selectedCategoryId == id;
    final chipColor = color ?? kPurple;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : kMuted,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        avatar: Icon(
          icon,
          size: 18,
          color: isSelected ? Colors.white : kMuted,
        ),
        backgroundColor: kCard2,
        selectedColor: chipColor,
        checkmarkColor: Colors.white,
        side: BorderSide(
          color: isSelected ? chipColor : kBorder,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onSelected: (selected) {
          setState(() {
            _selectedCategoryId = selected ? id : null;
          });
        },
      ),
    );
  }

  Widget _buildAddCategoryChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(
          'Add',
          style: GoogleFonts.outfit(color: kGold),
        ),
        avatar: const Icon(Icons.add, size: 18, color: kGold),
        backgroundColor: kCard2,
        side: const BorderSide(color: kGold),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onPressed: _showAddCategoryDialog,
      ),
    );
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    String selectedColor = '#7B6FE0';
    const String selectedIcon = 'folder';

    final colors = [
      '#7B6FE0',
      '#3DBA6F',
      '#F5C542',
      '#E05555',
      '#2196F3',
      '#9C27B0',
      '#FF9800',
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kCard2,
          title: Text(
            'Add Category',
            style: GoogleFonts.outfit(color: kText),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: GoogleFonts.outfit(color: kText),
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    labelStyle: GoogleFonts.outfit(color: kMuted),
                    filled: true,
                    fillColor: kCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Color',
                  style: GoogleFonts.outfit(color: kMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors
                      .map(
                        (c) => GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _parseColor(c),
                              shape: BoxShape.circle,
                              border: selectedColor == c
                                  ? Border.all(color: kText, width: 2)
                                  : null,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.outfit(color: kMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  return;
                }
                await _createCategory(
                  nameController.text.trim(),
                  selectedColor,
                  selectedIcon,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPurple,
              ),
              child:
                  Text('Add', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCategory(
    String name,
    String color,
    String icon,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final id = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';
      final category = CredentialCategory(
        id: id,
        userId: user.uid,
        name: name,
        color: color,
        icon: icon,
        sortOrder: _categories.length,
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('credentialCategories')
          .doc(id)
          .set(category.toJson());

      await _loadCategories();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Category added',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error adding category: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCredentialsList() {
    final filtered = _filteredCredentials;

    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: kPurple,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final credential = filtered[index];
          return _buildCredentialCard(credential);
        },
      ),
    );
  }

  Widget _buildCredentialCard(Credential credential) {
    final category = _getCategory(credential.categoryId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToDetail(credential: credential),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Type Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color:
                        _getTypeColor(credential.type).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getTypeIcon(credential.type),
                    color: _getTypeColor(credential.type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              credential.title,
                              style: GoogleFonts.outfit(
                                color: kText,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (credential.isFavorite)
                            const Icon(Icons.star, color: kGold, size: 18),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (category != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _parseColor(category.color ?? '#7B6FE0')
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                category.name,
                                style: GoogleFonts.outfit(
                                  color:
                                      _parseColor(category.color ?? '#7B6FE0'),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _formatDate(credential.updatedAt),
                            style: GoogleFonts.outfit(
                              color: kMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: kMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔐', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty || _selectedCategoryId != null
                ? 'No credentials found'
                : 'No credentials yet',
            style: GoogleFonts.outfit(color: kText, fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty || _selectedCategoryId != null
                ? 'Try adjusting your filters'
                : 'Add your first credential to get started',
            style: GoogleFonts.outfit(color: kMuted),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _navigateToDetail,
            icon: const Icon(Icons.add),
            label: Text(
              'Add Credential',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToDetail({Credential? credential}) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => CredentialDetailScreen(
          credential: credential,
          categories: _categories,
        ),
      ),
    );
    await _loadData();
  }

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'work':
        return Icons.work_outline;
      case 'person':
        return Icons.person_outline;
      case 'account_balance':
        return Icons.account_balance_outlined;
      case 'people':
        return Icons.people_outline;
      case 'shopping_cart':
        return Icons.shopping_cart_outlined;
      case 'home':
        return Icons.home_outlined;
      case 'star':
        return Icons.star_outline;
      default:
        return Icons.folder_outlined;
    }
  }

  Color _parseColor(String? hexColor) {
    if (hexColor == null) {
      return kPurple;
    }
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return kPurple;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
