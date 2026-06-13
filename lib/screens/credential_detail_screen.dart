// ================================================================
// Credential Detail Screen - Add/Edit Credential
// Allin1 Super App - Allin1
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/credential.dart';
import '../models/credential_category.dart';

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

class CredentialDetailScreen extends StatefulWidget {
  final Credential? credential;
  final List<CredentialCategory> categories;

  const CredentialDetailScreen({
    super.key,
    this.credential,
    this.categories = const [],
  });

  @override
  State<CredentialDetailScreen> createState() => _CredentialDetailScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<Credential?>('credential', credential))
      ..add(IterableProperty<CredentialCategory>('categories', categories));
  }
}

class _CredentialDetailScreenState extends State<CredentialDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();

  CredentialType _selectedType = CredentialType.password;
  String? _selectedCategoryId;
  bool _isFavorite = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isSaving = false;

  bool get _isEditing => widget.credential != null;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    if (widget.credential != null) {
      final cred = widget.credential!;
      _titleController.text = cred.title;
      _selectedType = cred.type;
      _selectedCategoryId = cred.categoryId;
      _isFavorite = cred.isFavorite;

      // Decrypt fields if possible (for display)
      _usernameController.text = cred.encryptedUsername.isNotEmpty
          ? _decryptField(cred.encryptedUsername)
          : '';
      _passwordController.text = cred.encryptedPassword.isNotEmpty
          ? _decryptField(cred.encryptedPassword)
          : '';
      _urlController.text =
          cred.encryptedUrl != null ? _decryptField(cred.encryptedUrl!) : '';
      _notesController.text = cred.encryptedNotes != null
          ? _decryptField(cred.encryptedNotes!)
          : '';
    }
  }

  // Simple decode for demo - in production use proper encryption
  String _decryptField(String encrypted) {
    try {
      if (encrypted.isEmpty) {
        return '';
      }

      // Check if it looks like base64
      final base64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');
      if (encrypted.length > 20 && base64Regex.hasMatch(encrypted)) {
        try {
          final decoded = Uri.decodeFull(encrypted);
          return decoded;
        } catch (_) {
          return encrypted;
        }
      }
      return encrypted;
    } catch (_) {
      return encrypted;
    }
  }

  // Simple encode for demo - in production use proper encryption
  String _encryptField(String plain) {
    if (plain.isEmpty) {
      return '';
    }
    try {
      return Uri.encodeFull(plain);
    } catch (_) {
      return plain;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Credential' : 'Add Credential',
          style: GoogleFonts.outfit(
            color: kText,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: kRed),
              onPressed: _showDeleteDialog,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: kPurple),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTypeSelector(),
                    const SizedBox(height: 20),
                    _buildTitleField(),
                    const SizedBox(height: 16),
                    _buildUsernameField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(),
                    const SizedBox(height: 16),
                    _buildUrlField(),
                    const SizedBox(height: 16),
                    _buildCategoryDropdown(),
                    const SizedBox(height: 16),
                    _buildNotesField(),
                    const SizedBox(height: 16),
                    _buildFavoriteToggle(),
                    const SizedBox(height: 32),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CREDENTIAL TYPE',
          style: GoogleFonts.outfit(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: CredentialType.values.map(_buildTypeCard).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeCard(CredentialType type) {
    final isSelected = _selectedType == type;
    final color = _getTypeColor(type);

    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : kCard2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : kBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getTypeIcon(type),
              color: isSelected ? color : kMuted,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              type.displayName,
              style: GoogleFonts.outfit(
                color: isSelected ? color : kMuted,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleField() {
    return _buildTextField(
      controller: _titleController,
      label: 'Title',
      hint: 'e.g., Gmail, Netflix, Bank',
      icon: Icons.label_outline,
      validator: (v) => v!.isEmpty ? 'Title is required' : null,
    );
  }

  Widget _buildUsernameField() {
    final icon = _selectedType == CredentialType.bankAccount
        ? Icons.person_outline
        : Icons.email_outlined;

    return _buildTextField(
      controller: _usernameController,
      label: _selectedType == CredentialType.bankAccount
          ? 'Account Number'
          : 'Username / Email',
      hint: _selectedType == CredentialType.bankAccount
          ? 'Enter account number'
          : 'Enter username or email',
      icon: icon,
      keyboardType: _selectedType == CredentialType.bankAccount
          ? TextInputType.number
          : TextInputType.emailAddress,
    );
  }

  Widget _buildPasswordField() {
    return _buildTextField(
      controller: _passwordController,
      label: _getPasswordLabel(),
      hint: _getPasswordHint(),
      icon: Icons.lock_outline,
      obscureText: _obscurePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword ? Icons.visibility_off : Icons.visibility,
          color: kMuted,
        ),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    );
  }

  String _getPasswordLabel() {
    switch (_selectedType) {
      case CredentialType.password:
        return 'Password';
      case CredentialType.apiKey:
        return 'API Key';
      case CredentialType.bankAccount:
        return 'PIN / Password';
      case CredentialType.wifi:
        return 'WiFi Password';
      case CredentialType.card:
        return 'Card PIN';
      default:
        return 'Password / Secret';
    }
  }

  String _getPasswordHint() {
    switch (_selectedType) {
      case CredentialType.apiKey:
        return 'Enter API key';
      case CredentialType.wifi:
        return 'Enter WiFi password';
      case CredentialType.card:
        return 'Enter card PIN';
      default:
        return 'Enter password';
    }
  }

  Widget _buildUrlField() {
    if (_selectedType == CredentialType.secureNote ||
        _selectedType == CredentialType.wifi) {
      return const SizedBox.shrink();
    }

    return _buildTextField(
      controller: _urlController,
      label: 'Website URL',
      hint: 'https://example.com',
      icon: Icons.link,
      keyboardType: TextInputType.url,
    );
  }

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CATEGORY',
          style: GoogleFonts.outfit(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: kCard2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedCategoryId,
              isExpanded: true,
              dropdownColor: kCard2,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              hint: Text(
                'Select category (optional)',
                style: GoogleFonts.outfit(color: kMuted),
              ),
              icon: const Icon(Icons.keyboard_arrow_down, color: kMuted),
              items: [
                const DropdownMenuItem<String?>(
                  child: Text('None'),
                ),
                ...widget.categories.map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _parseColor(category.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          category.name,
                          style: GoogleFonts.outfit(color: kText),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _selectedCategoryId = value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return _buildTextField(
      controller: _notesController,
      label: 'Notes',
      hint: 'Add any additional notes...',
      icon: Icons.note_outlined,
      maxLines: 4,
    );
  }

  Widget _buildFavoriteToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_outline, color: kGold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mark as Favorite',
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Quick access from the top',
                  style: GoogleFonts.outfit(
                    color: kMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isFavorite,
            onChanged: (value) => setState(() => _isFavorite = value),
            activeThumbColor: kGold,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: GoogleFonts.outfit(color: kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(color: kMuted),
            prefixIcon: Icon(icon, color: kMuted, size: 20),
            suffixIcon: suffixIcon,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kRed),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: kMuted,
              side: const BorderSide(color: kBorder),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Cancel', style: GoogleFonts.outfit()),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveCredential,
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _isEditing ? 'Update' : 'Save',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveCredential() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final now = DateTime.now();
      final credentialId = widget.credential?.id ?? const Uuid().v4();

      final credential = Credential(
        id: credentialId,
        userId: user.uid,
        title: _titleController.text.trim(),
        type: _selectedType,
        encryptedUsername: _encryptField(_usernameController.text),
        encryptedPassword: _encryptField(_passwordController.text),
        encryptedUrl: _urlController.text.trim().isNotEmpty
            ? _encryptField(_urlController.text.trim())
            : null,
        encryptedNotes: _notesController.text.trim().isNotEmpty
            ? _encryptField(_notesController.text.trim())
            : null,
        categoryId: _selectedCategoryId,
        isFavorite: _isFavorite,
        isPinned: widget.credential?.isPinned ?? false,
        sharedWith: widget.credential?.sharedWith ?? [],
        createdAt: widget.credential?.createdAt ?? now,
        updatedAt: now,
      );

      await FirebaseFirestore.instance
          .collection('credentials')
          .doc(credentialId)
          .set(credential.toJson());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Credential updated' : 'Credential saved',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving credential: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showDeleteDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard2,
        title: Text(
          'Delete Credential?',
          style: GoogleFonts.outfit(color: kText),
        ),
        content: Text(
          'This action cannot be undone. The credential will be permanently deleted.',
          style: GoogleFonts.outfit(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: kMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteCredential();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
            ),
            child:
                Text('Delete', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCredential() async {
    if (widget.credential == null) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Soft delete - mark as deleted
      await FirebaseFirestore.instance
          .collection('credentials')
          .doc(widget.credential!.id)
          .update({
        'isDeleted': true,
        'updatedAt': DateTime.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Credential deleted',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting credential: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
