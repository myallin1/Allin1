// ================================================================
// Admin Credential Management Screen - Allin1 Super App
// ================================================================
// Administrative interface for managing user credentials,
// admin-created credentials, and user assignments.
// Uses Firebase Firestore for data storage.
//
// Author: NJ TECH
// Version: 1.0.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/credential.dart' hide Timestamp;
import '../../services/admin_credential_service.dart';
import '../../services/encryption_service.dart';

// ── Theme Colors ─────────────────────────────────────────────
const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kRed = Color(0xFFE05555);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

// ================================================================
// Admin Credentials Screen
// ================================================================
class CredentialsAdminScreen extends StatefulWidget {
  const CredentialsAdminScreen({super.key});

  @override
  State<CredentialsAdminScreen> createState() => _CredentialsAdminScreenState();
}

class _CredentialsAdminScreenState extends State<CredentialsAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Statistics
  int _totalCredentials = 0;
  Map<CredentialType, int> _credentialsByType = {};
  int _activeAssignments = 0;
  int _adminManagedCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStatistics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStatistics() async {
    try {
      // Get total user credentials
      final credentialsSnapshot =
          await FirebaseFirestore.instance.collection('credentials').get();

      // Get admin credentials
      final adminCredSnapshot =
          await FirebaseFirestore.instance.collection('adminCredentials').get();

      // Calculate credentials by type
      final byType = <CredentialType, int>{};
      for (final doc in credentialsSnapshot.docs) {
        final type =
            CredentialType.fromString(doc['type'] as String? ?? 'other');
        byType[type] = (byType[type] ?? 0) + 1;
      }

      // Count active assignments (credentials with assigned users)
      int assignments = 0;
      for (final doc in adminCredSnapshot.docs) {
        final assignedUsers = doc['assignedUserIds'] as List<dynamic>? ?? [];
        assignments += assignedUsers.length;
      }

      if (mounted) {
        setState(() {
          _totalCredentials = credentialsSnapshot.docs.length;
          _credentialsByType = byType;
          _adminManagedCount = adminCredSnapshot.docs.length;
          _activeAssignments = assignments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(
          'Credential Management',
          style: GoogleFonts.poppins(color: kText),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kPurple,
          labelColor: kPurple,
          unselectedLabelColor: kMuted,
          tabs: const [
            Tab(text: 'All User Credentials', icon: Icon(Icons.list_alt)),
            Tab(text: 'Admin Managed', icon: Icon(Icons.admin_panel_settings)),
            Tab(text: 'User Assignments', icon: Icon(Icons.assignment_ind)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : Column(
              children: [
                // Statistics Cards
                _buildStatisticsCards(),
                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _UserCredentialsView(onRefresh: _loadStatistics),
                      _AdminManagedView(onRefresh: _loadStatistics),
                      _UserAssignmentsView(onRefresh: _loadStatistics),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatisticsCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              icon: Icons.vpn_key,
              label: 'Total Credentials',
              value: '$_totalCredentials',
              color: kPurple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              icon: Icons.category,
              label: 'By Type',
              value: '${_credentialsByType.length}',
              color: kOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              icon: Icons.people,
              label: 'Active Assignments',
              value: '$_activeAssignments',
              color: kGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              icon: Icons.admin_panel_settings,
              label: 'Admin Managed',
              value: '$_adminManagedCount',
              color: kGold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: kText,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: kMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ================================================================
// User Credentials View Tab
// ================================================================
class _UserCredentialsView extends StatefulWidget {
  final VoidCallback onRefresh;

  const _UserCredentialsView({required this.onRefresh});

  @override
  State<_UserCredentialsView> createState() => _UserCredentialsViewState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onRefresh', onRefresh));
  }
}

class _UserCredentialsViewState extends State<_UserCredentialsView> {
  String _searchQuery = '';
  CredentialType? _selectedType;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and Filter Bar
        _buildSearchBar(),
        // Data Table
        Expanded(
          child: _buildCredentialsTable(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Search Field
          Expanded(
            flex: 2,
            child: TextField(
              style: const TextStyle(color: kText),
              decoration: InputDecoration(
                hintText: 'Search by title or owner...',
                hintStyle: const TextStyle(color: kMuted),
                prefixIcon: const Icon(Icons.search, color: kMuted),
                filled: true,
                fillColor: kCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPurple),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),
          const SizedBox(width: 16),
          // Filter Dropdown
          Expanded(
            child: DropdownButtonFormField<CredentialType?>(
              initialValue: _selectedType,
              dropdownColor: kCard,
              style: const TextStyle(color: kText),
              decoration: InputDecoration(
                labelText: 'Filter by Type',
                labelStyle: const TextStyle(color: kMuted),
                filled: true,
                fillColor: kCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kBorder),
                ),
              ),
              items: [
                const DropdownMenuItem(
                  child: Text('All Types'),
                ),
                ...CredentialType.values.map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedType = value);
              },
            ),
          ),
          const SizedBox(width: 16),
          // Export Button
          ElevatedButton.icon(
            onPressed: _exportCredentials,
            icon: const Icon(Icons.download),
            label: const Text('Export'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPurple,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('credentials')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: kPurple),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.vpn_key, color: kMuted, size: 64),
                SizedBox(height: 16),
                Text(
                  'No credentials found',
                  style: TextStyle(color: kText, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'User credentials will appear here',
                  style: TextStyle(color: kMuted),
                ),
              ],
            ),
          );
        }

        // Filter credentials
        final filteredCredentials = snapshot.data!.docs.where((doc) {
          final title = (doc['title'] as String? ?? '').toLowerCase();
          final userId = (doc['userId'] as String? ?? '').toLowerCase();
          final type =
              CredentialType.fromString(doc['type'] as String? ?? 'other');

          final bool matchesSearch = _searchQuery.isEmpty ||
              title.contains(_searchQuery) ||
              userId.contains(_searchQuery);

          final bool matchesType =
              _selectedType == null || type == _selectedType;

          return matchesSearch && matchesType;
        }).toList();

        if (filteredCredentials.isEmpty) {
          return const Center(
            child: Text(
              'No credentials match your filters',
              style: TextStyle(color: kMuted),
            ),
          );
        }

        return _buildDataTable(filteredCredentials);
      },
    );
  }

  Widget _buildDataTable(List<QueryDocumentSnapshot> credentials) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(kCard2),
            dataRowColor: WidgetStateProperty.all(kCard),
            dividerThickness: 1,
            columnSpacing: 24,
            columns: const [
              DataColumn(
                label: Text(
                  'Title',
                  style: TextStyle(
                    color: kPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Type',
                  style: TextStyle(
                    color: kPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Owner',
                  style: TextStyle(
                    color: kPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Category',
                  style: TextStyle(
                    color: kPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Created',
                  style: TextStyle(
                    color: kPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataColumn(
                label: Text(
                  'Actions',
                  style: TextStyle(
                    color: kPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            rows: credentials.map((doc) {
              final credential =
                  Credential.fromJson(doc.data()! as Map<String, dynamic>);
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      credential.title,
                      style: const TextStyle(color: kText),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getTypeColor(credential.type)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        credential.type.displayName,
                        style: TextStyle(
                          color: _getTypeColor(credential.type),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(credential.userId)
                          .get(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          final username =
                              snapshot.data!.get('username') as String? ??
                                  'Unknown';
                          return Text(
                            username,
                            style: const TextStyle(color: kText),
                          );
                        }
                        return const Text(
                          'Unknown',
                          style: TextStyle(color: kMuted),
                        );
                      },
                    ),
                  ),
                  DataCell(
                    FutureBuilder<DocumentSnapshot?>(
                      future: credential.categoryId != null
                          ? FirebaseFirestore.instance
                              .collection('credentialCategories')
                              .doc(credential.categoryId)
                              .get()
                          : Future<DocumentSnapshot?>.value(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData &&
                            snapshot.data != null &&
                            snapshot.data!.exists) {
                          return Text(
                            snapshot.data!.get('name') as String? ?? 'N/A',
                            style: const TextStyle(color: kText),
                          );
                        }
                        return const Text(
                          'N/A',
                          style: TextStyle(color: kMuted),
                        );
                      },
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatDate(credential.createdAt),
                      style: const TextStyle(color: kMuted),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.visibility,
                            color: kPurple,
                            size: 20,
                          ),
                          tooltip: 'View Details',
                          onPressed: () => _viewCredentialDetails(credential),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: kRed, size: 20),
                          tooltip: 'Delete',
                          onPressed: () => _deleteCredential(doc.id),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(CredentialType type) {
    switch (type) {
      case CredentialType.password:
        return kPurple;
      case CredentialType.apiKey:
        return kOrange;
      case CredentialType.secureNote:
        return kGreen;
      case CredentialType.bankAccount:
        return kGold;
      case CredentialType.wifi:
        return kPurple2;
      case CredentialType.card:
        return kRed;
      case CredentialType.other:
        return kMuted;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _viewCredentialDetails(Credential credential) async {
    // Decrypt credentials for admin view
    final encryption = EncryptionService();
    String? decryptedUsername;
    String? decryptedPassword;
    String? decryptedUrl;
    String? decryptedNotes;
    String? decryptedExtra;

    try {
      if (encryption.isInitialized) {
        decryptedUsername = encryption.decrypt(credential.encryptedUsername);
        decryptedPassword = encryption.decrypt(credential.encryptedPassword);
        if (credential.encryptedUrl != null) {
          decryptedUrl = encryption.decrypt(credential.encryptedUrl!);
        }
        if (credential.encryptedNotes != null) {
          decryptedNotes = encryption.decrypt(credential.encryptedNotes!);
        }
        if (credential.encryptedExtra != null) {
          decryptedExtra = encryption.decrypt(credential.encryptedExtra!);
        }
      } else {
        // Show encrypted if encryption not available
        decryptedUsername = credential.encryptedUsername;
        decryptedPassword = credential.encryptedPassword;
        decryptedUrl = credential.encryptedUrl;
        decryptedNotes = credential.encryptedNotes;
        decryptedExtra = credential.encryptedExtra;
      }
    } catch (e) {
      decryptedUsername = 'Error decrypting';
      decryptedPassword = 'Error decrypting';
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCard,
        title: Text(credential.title, style: const TextStyle(color: kText)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Type', credential.type.displayName),
              _detailRow('Username', decryptedUsername ?? 'N/A'),
              _detailRow('Password', decryptedPassword ?? 'N/A'),
              if (decryptedUrl != null && decryptedUrl.isNotEmpty)
                _detailRow('URL', decryptedUrl),
              if (decryptedNotes != null && decryptedNotes.isNotEmpty)
                _detailRow('Notes', decryptedNotes),
              if (decryptedExtra != null && decryptedExtra.isNotEmpty)
                _detailRow('Extra', decryptedExtra),
              const Divider(color: kBorder),
              _detailRow('Created', _formatDate(credential.createdAt)),
              _detailRow('Updated', _formatDate(credential.updatedAt)),
              _detailRow(
                'Shared With',
                '${credential.sharedWith.length} users',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style:
                  const TextStyle(color: kMuted, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: kText),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCredential(String credentialId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Delete Credential', style: TextStyle(color: kText)),
        content: const Text(
          'Are you sure you want to delete this credential? This action cannot be undone.',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('credentials')
            .doc(credentialId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Credential deleted successfully'),
              backgroundColor: kGreen,
            ),
          );
          widget.onRefresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting credential: $e'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    }
  }

  void _exportCredentials() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export functionality coming soon'),
        backgroundColor: kPurple,
      ),
    );
  }
}

// ================================================================
// Admin Managed Credentials View Tab
// ================================================================
class _AdminManagedView extends StatefulWidget {
  final VoidCallback onRefresh;

  const _AdminManagedView({required this.onRefresh});

  @override
  State<_AdminManagedView> createState() => _AdminManagedViewState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onRefresh', onRefresh));
  }
}

class _AdminManagedViewState extends State<_AdminManagedView> {
  final _encryption = EncryptionService();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Create Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _showCreateCredentialDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create Admin Credential'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ],
          ),
        ),
        // Admin Credentials List
        Expanded(
          child: _buildAdminCredentialsList(),
        ),
      ],
    );
  }

  Widget _buildAdminCredentialsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('adminCredentials')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: kPurple),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.admin_panel_settings, color: kMuted, size: 64),
                SizedBox(height: 16),
                Text(
                  'No admin credentials',
                  style: TextStyle(color: kText, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Create admin credentials to assign to users',
                  style: TextStyle(color: kMuted),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final adminCred =
                AdminCredential.fromJson(doc.data()! as Map<String, dynamic>);
            return _adminCredentialCard(adminCred, doc.id);
          },
        );
      },
    );
  }

  Widget _adminCredentialCard(AdminCredential credential, String docId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kPurple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getTypeIcon(credential.type),
                  color: kPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      credential.title,
                      style: const TextStyle(
                        color: kText,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      credential.type.displayName,
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Actions
              IconButton(
                icon: const Icon(Icons.edit, color: kOrange),
                tooltip: 'Edit',
                onPressed: () => _showEditCredentialDialog(credential, docId),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: kRed),
                tooltip: 'Delete',
                onPressed: () => _deleteAdminCredential(docId),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Assigned Users
          Row(
            children: [
              const Icon(Icons.people, color: kMuted, size: 16),
              const SizedBox(width: 8),
              Text(
                '${credential.assignedUserIds.length} users assigned',
                style: const TextStyle(color: kMuted),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showAssignUsersDialog(credential, docId),
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Manage Assignments'),
                style: TextButton.styleFrom(foregroundColor: kPurple),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(CredentialType type) {
    switch (type) {
      case CredentialType.password:
        return Icons.lock;
      case CredentialType.apiKey:
        return Icons.key;
      case CredentialType.secureNote:
        return Icons.note;
      case CredentialType.bankAccount:
        return Icons.account_balance;
      case CredentialType.wifi:
        return Icons.wifi;
      case CredentialType.card:
        return Icons.credit_card;
      case CredentialType.other:
        return Icons.folder;
    }
  }

  Future<void> _showCreateCredentialDialog() async {
    final titleController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final urlController = TextEditingController();
    final notesController = TextEditingController();
    CredentialType selectedType = CredentialType.password;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kCard,
          title: const Text(
            'Create Admin Credential',
            style: TextStyle(color: kText),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('Title'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<CredentialType>(
                  initialValue: selectedType,
                  dropdownColor: kCard2,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('Type'),
                  items: CredentialType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedType = value!);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('Username / Email'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  style: const TextStyle(color: kText),
                  obscureText: true,
                  decoration: _inputDecoration('Password / Secret'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('URL (optional)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  style: const TextStyle(color: kText),
                  maxLines: 3,
                  decoration: _inputDecoration('Notes (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: kPurple),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if ((result ?? false) && mounted) {
      await _createAdminCredential(
        title: titleController.text,
        type: selectedType,
        username: usernameController.text,
        password: passwordController.text,
        url: urlController.text.isNotEmpty ? urlController.text : null,
        notes: notesController.text.isNotEmpty ? notesController.text : null,
      );
    }
  }

  Future<void> _showEditCredentialDialog(
    AdminCredential credential,
    String docId,
  ) async {
    final String title = credential.title;
    CredentialType selectedType = credential.type;
    String username = credential.encryptedUsername;
    String password = credential.encryptedPassword;
    String? url = credential.encryptedUrl;
    String? notes = credential.encryptedNotes;

    // Try to decrypt for editing
    try {
      if (_encryption.isInitialized) {
        username = _encryption.decrypt(credential.encryptedUsername);
        password = _encryption.decrypt(credential.encryptedPassword);
        if (url != null) {
          url = _encryption.decrypt(url);
        }
        if (notes != null) {
          notes = _encryption.decrypt(notes);
        }
      }
    } catch (e) {
      // Keep encrypted values if decryption fails
    }

    final titleController = TextEditingController(text: title);
    final usernameController = TextEditingController(text: username);
    final passwordController = TextEditingController(text: password);
    final urlController = TextEditingController(text: url ?? '');
    final notesController = TextEditingController(text: notes ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kCard,
          title: const Text(
            'Edit Admin Credential',
            style: TextStyle(color: kText),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('Title'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<CredentialType>(
                  initialValue: selectedType,
                  dropdownColor: kCard2,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('Type'),
                  items: CredentialType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedType = value!);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('Username / Email'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  style: const TextStyle(color: kText),
                  obscureText: true,
                  decoration: _inputDecoration('Password / Secret'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: kText),
                  decoration: _inputDecoration('URL (optional)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  style: const TextStyle(color: kText),
                  maxLines: 3,
                  decoration: _inputDecoration('Notes (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: kPurple),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if ((result ?? false) && mounted) {
      await _updateAdminCredential(
        docId: docId,
        title: titleController.text,
        type: selectedType,
        username: usernameController.text,
        password: passwordController.text,
        url: urlController.text.isNotEmpty ? urlController.text : null,
        notes: notesController.text.isNotEmpty ? notesController.text : null,
      );
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: kMuted),
      filled: true,
      fillColor: kCard2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPurple),
      ),
    );
  }

  Future<void> _createAdminCredential({
    required String title,
    required CredentialType type,
    required String username,
    required String password,
    String? url,
    String? notes,
  }) async {
    try {
      final adminService = AdminCredentialService();
      final result = await adminService.createAdminCredential(
        title: title,
        type: type,
        username: username,
        password: password,
        url: url,
        notes: notes,
      );

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Admin credential created successfully'),
              backgroundColor: kGreen,
            ),
          );
          widget.onRefresh();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result.error}'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating credential: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _updateAdminCredential({
    required String docId,
    required String title,
    required CredentialType type,
    required String username,
    required String password,
    String? url,
    String? notes,
  }) async {
    try {
      // Encrypt fields
      String encryptedUsername = username;
      String encryptedPassword = password;
      String? encryptedUrl;
      String? encryptedNotes;

      if (_encryption.isInitialized) {
        encryptedUsername = _encryption.encrypt(username);
        encryptedPassword = _encryption.encrypt(password);
        if (url != null) {
          encryptedUrl = _encryption.encrypt(url);
        }
        if (notes != null) {
          encryptedNotes = _encryption.encrypt(notes);
        }
      }

      await FirebaseFirestore.instance
          .collection('adminCredentials')
          .doc(docId)
          .update({
        'title': title,
        'type': type.toJson(),
        'encryptedUsername': encryptedUsername,
        'encryptedPassword': encryptedPassword,
        if (encryptedUrl != null) 'encryptedUrl': encryptedUrl,
        if (encryptedNotes != null) 'encryptedNotes': encryptedNotes,
        'updatedAt': DateTime.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credential updated successfully'),
            backgroundColor: kGreen,
          ),
        );
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating credential: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _deleteAdminCredential(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCard,
        title: const Text(
          'Delete Admin Credential',
          style: TextStyle(color: kText),
        ),
        content: const Text(
          'Are you sure you want to delete this admin credential? All user assignments will be removed.',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('adminCredentials')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Credential deleted successfully'),
              backgroundColor: kGreen,
            ),
          );
          widget.onRefresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting credential: $e'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _showAssignUsersDialog(
    AdminCredential credential,
    String docId,
  ) async {
    // Get all users
    final usersSnapshot =
        await FirebaseFirestore.instance.collection('users').get();

    final users = usersSnapshot.docs.map((doc) {
      return {
        'id': doc.id,
        'username': doc.get('username') as String? ?? 'Unknown',
        'email': doc.get('email') as String? ?? '',
      };
    }).toList();

    final List<String> selectedUserIds = List.from(credential.assignedUserIds);
    if (!mounted) {
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kCard,
          title: const Text('Assign Users', style: TextStyle(color: kText)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                final isSelected = selectedUserIds.contains(user['id']);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value ?? false) {
                        selectedUserIds.add(user['id']!);
                      } else {
                        selectedUserIds.remove(user['id']);
                      }
                    });
                  },
                  title: Text(
                    user['username']!,
                    style: const TextStyle(color: kText),
                  ),
                  subtitle: Text(
                    user['email']!,
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                  activeColor: kPurple,
                  checkColor: kText,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: kPurple),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if ((result ?? false) && mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('adminCredentials')
            .doc(docId)
            .update({
          'assignedUserIds': selectedUserIds,
          'updatedAt': DateTime.now(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Assignments updated successfully'),
              backgroundColor: kGreen,
            ),
          );
          widget.onRefresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating assignments: $e'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    }
  }
}

// ================================================================
// User Assignments View Tab
// ================================================================
class _UserAssignmentsView extends StatefulWidget {
  final VoidCallback onRefresh;

  const _UserAssignmentsView({required this.onRefresh});

  @override
  State<_UserAssignmentsView> createState() => _UserAssignmentsViewState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onRefresh', onRefresh));
  }
}

class _UserAssignmentsViewState extends State<_UserAssignmentsView> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: const TextStyle(color: kText),
            decoration: InputDecoration(
              hintText: 'Search by user or credential...',
              hintStyle: const TextStyle(color: kMuted),
              prefixIcon: const Icon(Icons.search, color: kMuted),
              filled: true,
              fillColor: kCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kPurple),
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value.toLowerCase());
            },
          ),
        ),
        // Assignments Table
        Expanded(
          child: _buildAssignmentsTable(),
        ),
      ],
    );
  }

  Widget _buildAssignmentsTable() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance.collection('adminCredentials').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: kPurple),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_ind, color: kMuted, size: 64),
                SizedBox(height: 16),
                Text(
                  'No assignments found',
                  style: TextStyle(color: kText, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Create admin credentials and assign them to users',
                  style: TextStyle(color: kMuted),
                ),
              ],
            ),
          );
        }

        // Build list of assignments
        final List<_AssignmentRow> assignments = [];
        for (final doc in snapshot.data!.docs) {
          final adminCred =
              AdminCredential.fromJson(doc.data()! as Map<String, dynamic>);
          for (final userId in adminCred.assignedUserIds) {
            assignments.add(
              _AssignmentRow(
                credentialId: doc.id,
                credentialTitle: adminCred.title,
                credentialType: adminCred.type,
                userId: userId,
              ),
            );
          }
        }

        // Filter assignments
        final filteredAssignments = assignments.where((a) {
          if (_searchQuery.isEmpty) {
            return true;
          }
          return a.credentialTitle.toLowerCase().contains(_searchQuery) ||
              a.userId.toLowerCase().contains(_searchQuery);
        }).toList();

        if (filteredAssignments.isEmpty) {
          return const Center(
            child: Text(
              'No assignments match your search',
              style: TextStyle(color: kMuted),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(kCard2),
              dataRowColor: WidgetStateProperty.all(kCard),
              dividerThickness: 1,
              columnSpacing: 24,
              columns: const [
                DataColumn(
                  label: Text(
                    'Credential',
                    style: TextStyle(
                      color: kPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Type',
                    style: TextStyle(
                      color: kPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Assigned User',
                    style: TextStyle(
                      color: kPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Actions',
                    style: TextStyle(
                      color: kPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              rows: filteredAssignments.map((assignment) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        assignment.credentialTitle,
                        style: const TextStyle(color: kText),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getTypeColor(assignment.credentialType)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          assignment.credentialType.displayName,
                          style: TextStyle(
                            color: _getTypeColor(assignment.credentialType),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(assignment.userId)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData &&
                              snapshot.data != null &&
                              snapshot.data!.exists) {
                            final username =
                                snapshot.data!.get('username') as String? ??
                                    'Unknown';
                            final email =
                                snapshot.data!.get('email') as String? ?? '';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  username,
                                  style: const TextStyle(color: kText),
                                ),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    color: kMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          }
                          return const Text(
                            'Unknown User',
                            style: TextStyle(color: kMuted),
                          );
                        },
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: kRed,
                          size: 20,
                        ),
                        tooltip: 'Remove Assignment',
                        onPressed: () => _removeAssignment(
                          assignment.credentialId,
                          assignment.userId,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Color _getTypeColor(CredentialType type) {
    switch (type) {
      case CredentialType.password:
        return kPurple;
      case CredentialType.apiKey:
        return kOrange;
      case CredentialType.secureNote:
        return kGreen;
      case CredentialType.bankAccount:
        return kGold;
      case CredentialType.wifi:
        return kPurple2;
      case CredentialType.card:
        return kRed;
      case CredentialType.other:
        return kMuted;
    }
  }

  Future<void> _removeAssignment(String credentialId, String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Remove Assignment', style: TextStyle(color: kText)),
        content: const Text(
          'Are you sure you want to remove this user assignment?',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        // Get current assigned users
        final doc = await FirebaseFirestore.instance
            .collection('adminCredentials')
            .doc(credentialId)
            .get();

        final List<String> assignedUsers = List.from(
          doc.get('assignedUserIds') as List<dynamic>? ?? [],
        );
        assignedUsers.remove(userId);

        await FirebaseFirestore.instance
            .collection('adminCredentials')
            .doc(credentialId)
            .update({
          'assignedUserIds': assignedUsers,
          'updatedAt': DateTime.now(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Assignment removed successfully'),
              backgroundColor: kGreen,
            ),
          );
          widget.onRefresh();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error removing assignment: $e'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    }
  }
}

class _AssignmentRow {
  final String credentialId;
  final String credentialTitle;
  final CredentialType credentialType;
  final String userId;

  _AssignmentRow({
    required this.credentialId,
    required this.credentialTitle,
    required this.credentialType,
    required this.userId,
  });
}
