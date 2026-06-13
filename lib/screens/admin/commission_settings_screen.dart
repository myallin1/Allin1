// ================================================================
// Commission & Fee Settings Screen - Admin Panel
// Allin1 Super App v1.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/platform_settings.dart';
import '../../services/platform_settings_service.dart';

class CommissionSettingsScreen extends StatefulWidget {
  const CommissionSettingsScreen({super.key});

  @override
  State<CommissionSettingsScreen> createState() =>
      _CommissionSettingsScreenState();
}

class _CommissionSettingsScreenState extends State<CommissionSettingsScreen> {
  final PlatformSettingsService _settingsService = PlatformSettingsService();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  // Form controllers for Rider Commission
  final _bikeTaxiController = TextEditingController();
  final _baseFareController = TextEditingController(); // ₹ base fare
  final _perKmFareController = TextEditingController(); // ₹ per km
  final _autoController = TextEditingController();
  final _carController = TextEditingController();
  final _deliveryController = TextEditingController();
  final _foodDeliveryController = TextEditingController();
  final _groceryController = TextEditingController();
  final _minEarningController = TextEditingController();
  final _peakMultiplierController = TextEditingController();

  // Form controllers for Seller Commission
  final _foodSellerController = TextEditingController();
  final _grocerySellerController = TextEditingController();
  final _techSellerController = TextEditingController();
  final _pharmacySellerController = TextEditingController();
  final _generalSellerController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _flatFeeController = TextEditingController();

  // Form controllers for Platform Fee
  final _gatewayFeeController = TextEditingController();
  final _coinValueCtrl = TextEditingController(text: '100');
  bool _upiZeroFee = true;

  // Form controllers for Delivery Settings
  final _baseDeliveryController = TextEditingController();
  final _freeDeliveryController = TextEditingController();
  final _perKmController = TextEditingController();
  final _expressFeeController = TextEditingController();
  final _scheduledFeeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    // Dispose all controllers
    _bikeTaxiController.dispose();
    _baseFareController.dispose();
    _perKmFareController.dispose();
    _autoController.dispose();
    _carController.dispose();
    _deliveryController.dispose();
    _foodDeliveryController.dispose();
    _groceryController.dispose();
    _minEarningController.dispose();
    _peakMultiplierController.dispose();
    _foodSellerController.dispose();
    _grocerySellerController.dispose();
    _techSellerController.dispose();
    _pharmacySellerController.dispose();
    _generalSellerController.dispose();
    _minOrderController.dispose();
    _flatFeeController.dispose();
    _gatewayFeeController.dispose();
    _coinValueCtrl.dispose();
    _baseDeliveryController.dispose();
    _freeDeliveryController.dispose();
    _perKmController.dispose();
    _expressFeeController.dispose();
    _scheduledFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = await _settingsService.getSettings();
      _populateControllers(settings);
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _populateControllers(PlatformSettings settings) {
    // Rider Commission
    _bikeTaxiController.text =
        settings.riderCommission.bikeTaxiPercent.toString();
    // Load bike taxi fare rates directly from Firestore top-level fields
    FirebaseFirestore.instance
        .collection('platformSettings')
        .doc('global')
        .get()
        .then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data() ?? {};
        setState(() {
          _baseFareController.text =
              (d['bikeTaxiBaseFare'] as num?)?.toString() ?? '25';
          _perKmFareController.text =
              (d['bikeTaxiPerKm'] as num?)?.toString() ?? '12';
        });
      }
    }).catchError((_) {
      _baseFareController.text = '25';
      _perKmFareController.text = '12';
    });
    _autoController.text = settings.riderCommission.autoPercent.toString();
    _carController.text = settings.riderCommission.carPercent.toString();
    _deliveryController.text =
        settings.riderCommission.deliveryPercent.toString();
    _foodDeliveryController.text =
        settings.riderCommission.foodDeliveryPercent.toString();
    _groceryController.text =
        settings.riderCommission.groceryPercent.toString();
    _minEarningController.text =
        settings.riderCommission.minimumEarning.toString();
    _peakMultiplierController.text =
        settings.riderCommission.peakHourMultiplier.toString();

    // Seller Commission
    _foodSellerController.text =
        settings.sellerCommission.foodPercent.toString();
    _grocerySellerController.text =
        settings.sellerCommission.groceryPercent.toString();
    _techSellerController.text =
        settings.sellerCommission.techPercent.toString();
    _pharmacySellerController.text =
        settings.sellerCommission.pharmacyPercent.toString();
    _generalSellerController.text =
        settings.sellerCommission.generalPercent.toString();
    _minOrderController.text =
        settings.sellerCommission.minimumOrder?.toString() ?? '100';
    _flatFeeController.text =
        settings.sellerCommission.flatFeeBelowMin?.toString() ?? '15';

    // Platform Fee
    _gatewayFeeController.text =
        settings.platformFee.paymentGatewayFee.toString();
    _upiZeroFee = settings.platformFee.upiZeroFee;

    // Load coinValue from platformSettings/global
    FirebaseFirestore.instance
        .collection('platformSettings')
        .doc('global')
        .get()
        .then((doc) {
      if (doc.exists && mounted) {
        final d = doc.data() ?? {};
        setState(() {
          _coinValueCtrl.text = (d['coinValue'] ?? 100).toString();
        });
      }
    }).catchError((_) {
      _coinValueCtrl.text = '100';
    });

    // Delivery Settings
    _baseDeliveryController.text =
        settings.deliverySettings.baseDeliveryFee.toString();
    _freeDeliveryController.text =
        settings.deliverySettings.freeDeliveryThreshold.toString();
    _perKmController.text = settings.deliverySettings.perKmRate.toString();
    _expressFeeController.text =
        settings.deliverySettings.expressDeliveryFee.toString();
    _scheduledFeeController.text =
        settings.deliverySettings.scheduledDeliveryFee.toString();
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'system';

      final updatedSettings = PlatformSettings(
        riderCommission: RiderCommission(
          bikeTaxiPercent: double.tryParse(_bikeTaxiController.text) ?? 15.0,
          autoPercent: double.tryParse(_autoController.text) ?? 15.0,
          carPercent: double.tryParse(_carController.text) ?? 12.0,
          deliveryPercent: double.tryParse(_deliveryController.text) ?? 15.0,
          foodDeliveryPercent:
              double.tryParse(_foodDeliveryController.text) ?? 18.0,
          groceryPercent: double.tryParse(_groceryController.text) ?? 18.0,
          minimumEarning: double.tryParse(_minEarningController.text) ?? 30.0,
          peakHourMultiplier:
              double.tryParse(_peakMultiplierController.text) ?? 1.5,
        ),
        sellerCommission: SellerCommission(
          foodPercent: double.tryParse(_foodSellerController.text) ?? 20.0,
          groceryPercent:
              double.tryParse(_grocerySellerController.text) ?? 18.0,
          techPercent: double.tryParse(_techSellerController.text) ?? 15.0,
          pharmacyPercent:
              double.tryParse(_pharmacySellerController.text) ?? 15.0,
          generalPercent:
              double.tryParse(_generalSellerController.text) ?? 15.0,
          minimumOrder: double.tryParse(_minOrderController.text),
          flatFeeBelowMin: double.tryParse(_flatFeeController.text),
        ),
        platformFee: PlatformFee(
          paymentGatewayFee: double.tryParse(_gatewayFeeController.text) ?? 2.0,
          upiZeroFee: _upiZeroFee,
        ),
        deliverySettings: DeliverySettings(
          baseDeliveryFee:
              double.tryParse(_baseDeliveryController.text) ?? 30.0,
          freeDeliveryThreshold:
              double.tryParse(_freeDeliveryController.text) ?? 200.0,
          perKmRate: double.tryParse(_perKmController.text) ?? 5.0,
          minimumDistanceKm: 2,
          expressDeliveryFee:
              double.tryParse(_expressFeeController.text) ?? 50.0,
          scheduledDeliveryFee:
              double.tryParse(_scheduledFeeController.text) ?? 20.0,
          tiers: DeliverySettings.defaults().tiers,
        ),
        updatedAt: DateTime.now(),
        updatedBy: adminId,
      );

      await _settingsService.updateSettings(updatedSettings, adminId: adminId);

      // Also save fare rates as top-level fields for BookingScreen to read
      await FirebaseFirestore.instance
          .collection('platformSettings')
          .doc('global')
          .set(
        {
          'bikeTaxiBaseFare': double.tryParse(_baseFareController.text) ?? 25.0,
          'bikeTaxiPerKm': double.tryParse(_perKmFareController.text) ?? 12.0,
          'coinValue': int.tryParse(_coinValueCtrl.text) ?? 100,
        },
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'Are you sure you want to reset all settings to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      try {
        final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'system';
        await _settingsService.resetToDefaults(adminId: adminId);
        await _loadSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Settings reset to defaults'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error resetting settings: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Commission & Fee Settings',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettings,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      ElevatedButton(
                        onPressed: _loadSettings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRiderCommissionCard(),
                      const SizedBox(height: 16),
                      _buildSellerCommissionCard(),
                      const SizedBox(height: 16),
                      _buildPlatformFeeCard(),
                      const SizedBox(height: 16),
                      _buildDeliverySettingsCard(),
                      const SizedBox(height: 24),
                      _buildActionButtons(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF16213E)),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF16213E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? prefix,
    String? suffix,
    String? hintText,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType ?? TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixText: prefix,
          suffixText: suffix,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildRiderCommissionCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Rider Commission', Icons.motorcycle),
            const Divider(),
            // ── Bike Taxi Fare Rates ─────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '🏍️ Bike Taxi Fare Rates',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF16213E),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _baseFareController,
                    label: 'Base Fare',
                    prefix: '₹',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _perKmFareController,
                    label: 'Per KM Rate',
                    prefix: '₹',
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _bikeTaxiController,
                    label: 'Bike Taxi',
                    suffix: '%',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _autoController,
                    label: 'Auto',
                    suffix: '%',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _carController,
                    label: 'Car',
                    suffix: '%',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _deliveryController,
                    label: 'Delivery',
                    suffix: '%',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _foodDeliveryController,
                    label: 'Food Delivery',
                    suffix: '%',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _groceryController,
                    label: 'Grocery',
                    suffix: '%',
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _minEarningController,
                    label: 'Min Guarantee',
                    prefix: '₹',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _peakMultiplierController,
                    label: 'Peak Multiplier',
                    suffix: 'x',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerCommissionCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Seller Commission', Icons.store),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _foodSellerController,
                    label: 'Food',
                    suffix: '%',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _grocerySellerController,
                    label: 'Grocery',
                    suffix: '%',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _techSellerController,
                    label: 'Tech',
                    suffix: '%',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _pharmacySellerController,
                    label: 'Pharmacy',
                    suffix: '%',
                  ),
                ),
              ],
            ),
            _buildTextField(
              controller: _generalSellerController,
              label: 'General',
              suffix: '%',
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _minOrderController,
                    label: 'Min Order (for flat fee)',
                    prefix: '₹',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _flatFeeController,
                    label: 'Flat Fee Below Min',
                    prefix: '₹',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformFeeCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Platform Fees', Icons.payment),
            const Divider(),
            _buildTextField(
              controller: _gatewayFeeController,
              label: 'Payment Gateway Fee',
              suffix: '%',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _coinValueCtrl,
              label: '🪙 Coin Value (1 INR = ? Coins)',
              hintText: '100',
              suffix: 'coins',
              keyboardType: TextInputType.number,
            ),
            SwitchListTile(
              title: const Text('Zero UPI Fees'),
              subtitle: const Text('No extra charges for UPI payments'),
              value: _upiZeroFee,
              onChanged: (value) {
                setState(() {
                  _upiZeroFee = value;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliverySettingsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Delivery Settings', Icons.local_shipping),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _baseDeliveryController,
                    label: 'Base Delivery Fee',
                    prefix: '₹',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _freeDeliveryController,
                    label: 'Free Above',
                    prefix: '₹',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _perKmController,
                    label: 'Per KM Rate',
                    prefix: '₹',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _expressFeeController,
                    label: 'Express Fee',
                    prefix: '₹',
                  ),
                ),
              ],
            ),
            _buildTextField(
              controller: _scheduledFeeController,
              label: 'Scheduled Delivery Fee',
              prefix: '₹',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _resetToDefaults,
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16213E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
