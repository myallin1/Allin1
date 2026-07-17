// ================================================================
// Fare Management Screen - Admin App
// Dynamically update ride pricing for Bike, Auto, and Cab
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FareManagementScreen extends StatefulWidget {
  const FareManagementScreen({super.key});

  @override
  State<FareManagementScreen> createState() => _FareManagementScreenState();
}

class _FareManagementScreenState extends State<FareManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Theme Colors
  static const Color _bg = Color(0xFF0A0A1A);
  static const Color _surface = Color(0xFF12121E);
  static const Color _card = Color(0xFF1A1A2E);
  static const Color _primary = Color(0xFFE05555); // Admin Primary Red
  static const Color _secondary = Color(0xFFF5C542); // Admin Secondary Yellow
  static const Color _green = Color(0xFF00C853);
  static const Color _text = Color(0xFFEEEEF5);
  static const Color _muted = Color(0xFF7777A0);
  static const Color _border = Color(0x1AFFFFFF);

  bool _isLoading = true;

  // Controllers for Bike Taxi
  final TextEditingController _bikeBaseFareCtrl = TextEditingController();
  final TextEditingController _bikePerKmCtrl = TextEditingController();
  final TextEditingController _bikeBaseDistanceCtrl = TextEditingController();
  bool _bikeSaving = false;

  // Controllers for Auto
  final TextEditingController _autoBaseFareCtrl = TextEditingController();
  final TextEditingController _autoPerKmCtrl = TextEditingController();
  final TextEditingController _autoBaseDistanceCtrl = TextEditingController();
  bool _autoSaving = false;

  // Controllers for Cab
  final TextEditingController _cabBaseFareCtrl = TextEditingController();
  final TextEditingController _cabPerKmCtrl = TextEditingController();
  final TextEditingController _cabBaseDistanceCtrl = TextEditingController();
  bool _cabSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchFares();
  }

  @override
  void dispose() {
    _bikeBaseFareCtrl.dispose();
    _bikePerKmCtrl.dispose();
    _bikeBaseDistanceCtrl.dispose();
    _autoBaseFareCtrl.dispose();
    _autoPerKmCtrl.dispose();
    _autoBaseDistanceCtrl.dispose();
    _cabBaseFareCtrl.dispose();
    _cabPerKmCtrl.dispose();
    _cabBaseDistanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchFares() async {
    try {
      final doc =
          await _firestore.collection('settings').doc('ride_fares').get();
      if (doc.exists) {
        final data = doc.data() ?? {};

        // Bike
        final bike = data['bike'] as Map<String, dynamic>? ?? {};
        _bikeBaseFareCtrl.text = (bike['baseFare'] ?? '25').toString();
        _bikePerKmCtrl.text = (bike['perKm'] ?? '10').toString();
        _bikeBaseDistanceCtrl.text = (bike['baseDistance'] ?? '2').toString();

        // Auto
        final auto = data['auto'] as Map<String, dynamic>? ?? {};
        _autoBaseFareCtrl.text = (auto['baseFare'] ?? '30').toString();
        _autoPerKmCtrl.text = (auto['perKm'] ?? '12').toString();
        _autoBaseDistanceCtrl.text = (auto['baseDistance'] ?? '2').toString();

        // Cab
        final cab = data['cab'] as Map<String, dynamic>? ?? {};
        _cabBaseFareCtrl.text = (cab['baseFare'] ?? '50').toString();
        _cabPerKmCtrl.text = (cab['perKm'] ?? '15').toString();
        _cabBaseDistanceCtrl.text = (cab['baseDistance'] ?? '2').toString();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching fares: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveFares(String type) async {
    setState(() {
      if (type == 'bike') {
        _bikeSaving = true;
      }
      if (type == 'auto') {
        _autoSaving = true;
      }
      if (type == 'cab') {
        _cabSaving = true;
      }
    });

    try {
      final Map<String, dynamic> updateData = {};

      if (type == 'bike') {
        updateData['bike'] = {
          'baseFare': double.tryParse(_bikeBaseFareCtrl.text) ?? 25.0,
          'perKm': double.tryParse(_bikePerKmCtrl.text) ?? 10.0,
          'baseDistance': double.tryParse(_bikeBaseDistanceCtrl.text) ?? 2.0,
        };
      } else if (type == 'auto') {
        updateData['auto'] = {
          'baseFare': double.tryParse(_autoBaseFareCtrl.text) ?? 30.0,
          'perKm': double.tryParse(_autoPerKmCtrl.text) ?? 12.0,
          'baseDistance': double.tryParse(_autoBaseDistanceCtrl.text) ?? 2.0,
        };
      } else if (type == 'cab') {
        updateData['cab'] = {
          'baseFare': double.tryParse(_cabBaseFareCtrl.text) ?? 50.0,
          'perKm': double.tryParse(_cabPerKmCtrl.text) ?? 15.0,
          'baseDistance': double.tryParse(_cabBaseDistanceCtrl.text) ?? 2.0,
        };
      }

      await _firestore.collection('settings').doc('ride_fares').set(
            updateData,
            SetOptions(merge: true),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fares Updated Successfully ✅'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update Failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (type == 'bike') {
            _bikeSaving = false;
          }
          if (type == 'auto') {
            _autoSaving = false;
          }
          if (type == 'cab') {
            _cabSaving = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'Fare Management',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: _text),
        ),
        backgroundColor: _surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: _muted),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchFares();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildFareCard(
                    title: 'Bike Taxi',
                    icon: Icons.motorcycle,
                    emoji: '🏍️',
                    baseFareCtrl: _bikeBaseFareCtrl,
                    perKmCtrl: _bikePerKmCtrl,
                    baseDistCtrl: _bikeBaseDistanceCtrl,
                    isSaving: _bikeSaving,
                    onSave: () => _saveFares('bike'),
                  ),
                  const SizedBox(height: 20),
                  _buildFareCard(
                    title: 'Auto Rickshaw',
                    icon: Icons.electric_rickshaw,
                    emoji: '🛺',
                    baseFareCtrl: _autoBaseFareCtrl,
                    perKmCtrl: _autoPerKmCtrl,
                    baseDistCtrl: _autoBaseDistanceCtrl,
                    isSaving: _autoSaving,
                    onSave: () => _saveFares('auto'),
                  ),
                  const SizedBox(height: 20),
                  _buildFareCard(
                    title: 'Cab / Car',
                    icon: Icons.directions_car,
                    emoji: '🚘',
                    baseFareCtrl: _cabBaseFareCtrl,
                    perKmCtrl: _cabPerKmCtrl,
                    baseDistCtrl: _cabBaseDistanceCtrl,
                    isSaving: _cabSaving,
                    onSave: () => _saveFares('cab'),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildFareCard({
    required String title,
    required IconData icon,
    required String emoji,
    required TextEditingController baseFareCtrl,
    required TextEditingController perKmCtrl,
    required TextEditingController baseDistCtrl,
    required bool isSaving,
    required VoidCallback onSave,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _secondary, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  '$emoji $title',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildField(
                  label: 'Base Fare',
                  controller: baseFareCtrl,
                  suffix: '₹',
                  hint: 'Starting price',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Per KM Fare',
                  controller: perKmCtrl,
                  suffix: '₹/KM',
                  hint: 'Distance rate',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Base Distance',
                  controller: baseDistCtrl,
                  suffix: 'KM',
                  hint: 'Included in base fare',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Save Changes',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String suffix,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: _muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _muted.withValues(alpha: 0.5)),
            suffixText: suffix,
            suffixStyle: GoogleFonts.outfit(
              color: _secondary,
              fontWeight: FontWeight.bold,
            ),
            filled: true,
            fillColor: _bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}
