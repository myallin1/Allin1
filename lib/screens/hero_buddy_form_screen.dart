import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _coBg = Color(0xFF0C0A14);
const Color _coSurface = Color(0xFF15121F);
const Color _coPink = Color(0xFFFF4FA3);
const Color _coBorder = Color(0x33FF4FA3);
const String _phone = '919597879191';

class HeroBuddyFormScreen extends StatefulWidget {
  const HeroBuddyFormScreen({super.key});
  @override
  State<HeroBuddyFormScreen> createState() => _HeroBuddyFormScreenState();
}

class _HeroBuddyFormScreenState extends State<HeroBuddyFormScreen> {
  final List<TextEditingController> _taskControllers = [
    TextEditingController(),
  ];
  final TextEditingController _instructionCtrl = TextEditingController();
  bool _isSearching = false;

  void _addTaskField() =>
      setState(() => _taskControllers.add(TextEditingController()));

  void _removeTaskField(int index) {
    if (_taskControllers.length > 1) {
      setState(() {
        _taskControllers[index].dispose();
        _taskControllers.removeAt(index);
      });
    }
  }

  Future<void> _placeOrder() async {
    if (_taskControllers.first.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one task!')),
      );
      return;
    }
    setState(() => _isSearching = true);
    await Future.delayed(const Duration(seconds: 15));
    if (!mounted) {
      return;
    }
    setState(() => _isSearching = false);
    _showTimeoutDialog();
  }

  void _showTimeoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _coSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: _coBorder),
        ),
        title: Text(
          'Heroes are Busy! ⏳',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'All our local heroes are currently busy. Please try again or call our booking center directly for manual assignment.',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Try Again',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _coPink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse('tel:+$_phone');
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
            icon: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 18,
            ),
            label: Text(
              'Call Center',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _taskControllers) {
      c.dispose();
    }
    _instructionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _coBg,
      appBar: AppBar(
        backgroundColor: _coBg,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text(
          'Multi-Task Booking',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: _isSearching ? _buildSearchingUI() : _buildFormUI(),
      bottomNavigationBar: !_isSearching ? _buildBottomBar() : null,
    );
  }

  Widget _buildFormUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('What should our Hero do?'),
          ..._taskControllers
              .asMap()
              .entries
              .map((e) => _buildTaskField(e.key, e.value)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _addTaskField,
              icon: const Icon(
                Icons.add_circle_outline,
                color: _coPink,
                size: 18,
              ),
              label: Text(
                'Add Another Item/Task',
                style: GoogleFonts.outfit(
                  color: _coPink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('Special Instructions'),
          TextField(
            controller: _instructionCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration:
                _inputDeco('Any shop name, brand preference, or warnings?'),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Image Attachment'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _coSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_upload_outlined,
                  color: Colors.white54,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  'Upload reference picture (Optional)',
                  style: GoogleFonts.outfit(color: Colors.white54),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                  ),
                  onPressed: () {},
                  child: const Text(
                    'Choose Image',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 8),
        child: Text(
          title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _buildTaskField(int index, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _coSurface,
              shape: BoxShape.circle,
              border: Border.all(color: _coBorder),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: _coPink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Type item/task... (e.g., Get 2 Tea)'),
            ),
          ),
          if (_taskControllers.length > 1)
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Colors.white38,
              ),
              onPressed: () => _removeTaskField(index),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        filled: true,
        fillColor: _coSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _coPink),
        ),
      );

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _coSurface,
        border: Border(top: BorderSide(color: _coBorder)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivery Fee: ₹30',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Within 3KM limit',
                    style: GoogleFonts.outfit(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _coPink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _placeOrder,
              child: Text(
                'Place Order',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingUI() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _coPink),
            const SizedBox(height: 24),
            Text(
              'Finding a local Hero for you...',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Usually takes less than 3 minutes',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
}
