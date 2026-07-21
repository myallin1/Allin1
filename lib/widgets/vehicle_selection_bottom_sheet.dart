import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/fare_rates.dart';
import '../models/ride_model.dart';

const Color _brandPink = Color(0xFFFF4FA3);
const Color _brandPurple = Color(0xFFB21FFF);
const Color _brandText = Color(0xFF3D1230);
const Color _brandMuted = Color(0xFF8F5A78);
const Color _brandBorder = Color(0x33FF4FA3);

class VehicleSelectionBottomSheet extends StatefulWidget {
  final double distanceKm;
  final Map<String, dynamic>? fares;
  final void Function(String vehicleType, double estimatedFare) onConfirm;
  final String initialVehicleType;

  const VehicleSelectionBottomSheet({
    required this.distanceKm,
    required this.onConfirm,
    this.fares,
    this.initialVehicleType = 'bike',
    super.key,
  });

  @override
  State<VehicleSelectionBottomSheet> createState() => _VehicleSelectionBottomSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('distanceKm', distanceKm));
    properties.add(DiagnosticsProperty<Map<String, dynamic>?>('fares', fares));
    properties.add(ObjectFlagProperty<void Function(String vehicleType, double estimatedFare)>.has('onConfirm', onConfirm));
    properties.add(StringProperty('initialVehicleType', initialVehicleType));
  }
}

class _VehicleSelectionBottomSheetState extends State<VehicleSelectionBottomSheet>
    with SingleTickerProviderStateMixin {
  late String _selectedVehicle;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.initialVehicleType;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Resolves the estimated fare for [vehicleType] at [distanceKm].
  ///
  /// Bike uses FareRates (hardcoded day/night rates, resolved against
  /// the CURRENT time — this is a pre-ride estimate, so booking-time
  /// rate is correct here even though the final bill re-resolves at
  /// completion time). Every other vehicle type is unchanged — still
  /// RideModel.calculateFare() against the Firestore-backed
  /// widget.fares map, exactly as before.
  double _resolveFare(String vehicleType, double distanceKm) {
    if (vehicleType == 'bike') {
      final perKm = FareRates.resolveBikePerKm(DateTime.now());
      return FareRates.calculateBikeFare(
        distanceKm: distanceKm,
        perKm: perKm,
      );
    }
    return RideModel.calculateFare(
      distanceKm,
      vehicleType,
      fares: widget.fares,
    );
  }

  // Enhanced vehicle configuration with modern details
  final List<Map<String, dynamic>> _vehicles = [
    {
      'type': 'bike',
      'title': 'Bike Taxi',
      'subtitle': 'Fast & economical',
      'description': 'Perfect for short trips',
      'icon': '🏍️',
      'eta': '2-3 mins',
      'capacity': 1,
      'color': _brandPink,
      'bgColor': _brandPink.withValues(alpha: 0.1),
    },
    {
      'type': 'auto',
      'title': 'Auto Rickshaw',
      'subtitle': 'Comfortable & reliable',
      'description': 'Great for small groups',
      'icon': '🛺',
      'eta': '3-5 mins',
      'capacity': 3,
      'color': _brandPink,
      'bgColor': _brandPink.withValues(alpha: 0.1),
    },
    {
      'type': 'cab',
      'title': 'Mini Cab',
      'subtitle': 'Premium & spacious',
      'description': 'Luxury experience',
      'icon': '🚘',
      'eta': '4-6 mins',
      'capacity': 4,
      'color': _brandPink,
      'bgColor': _brandPink.withValues(alpha: 0.1),
    },
    {
      'type': 'parcel',
      'title': 'Parcel Delivery',
      'subtitle': 'Fast package drop',
      'description': 'Perfect for local parcel trips',
      'icon': '📦',
      'eta': '3-5 mins',
      'capacity': 1,
      'color': _brandPink,
      'bgColor': _brandPink.withValues(alpha: 0.1),
    },
    // T2: Emergency Manpower added to complete the 5-category pipeline
    {
      'type': 'emergency_manpower',
      'title': 'Emergency Manpower',
      'subtitle': 'SOS first responder',
      'description': 'Urgent on-ground assistance',
      'icon': '🚨',
      'eta': '5-8 mins',
      'capacity': 1,
      'color': Color(0xFFFF5252),
      'bgColor': Color(0x1AFF5252),
    },
    // Cargo pair: mini_truck + lorry. Uses _isCargoRide-style status
    // labels downstream (hero_ride_screen.dart) once a real ride exists.
    {
      'type': 'mini_truck',
      'title': 'Mini Truck',
      'subtitle': 'Small cargo & goods',
      'description': 'For bulky local deliveries',
      'icon': '🛻',
      'eta': '6-10 mins',
      'capacity': 1,
      'color': _brandPink,
      'bgColor': _brandPink.withValues(alpha: 0.1),
    },
    {
      'type': 'lorry',
      'title': 'Lorry',
      'subtitle': 'Heavy cargo transport',
      'description': 'For large-scale hauling',
      'icon': '🚚',
      'eta': '8-15 mins',
      'capacity': 1,
      'color': _brandPink,
      'bgColor': _brandPink.withValues(alpha: 0.1),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0xFFFFF1F8),
            ],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: _brandPink.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 24, left: 24, right: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Enhanced Drag Handle
                Center(
                  child: Container(
                    width: 56,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Modern Header with Distance
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose your ride',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          color: _brandText,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.distanceKm.toStringAsFixed(1)} km trip',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: _brandMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _brandPink.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.directions_car_rounded,
                        color: _brandPink,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Enhanced Vehicle List
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _vehicles.length,
                  itemBuilder: (context, index) => _buildVehicleCard(_vehicles[index]),
                ),

                const SizedBox(height: 32),

                // Premium Confirm Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_brandPink, _brandPurple],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _brandPink.withValues(alpha: 0.26),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      debugPrint('🔥 [BUTTON CLICKED] Confirm Booking button was tapped!');
                      final fare =
                          _resolveFare(_selectedVehicle, widget.distanceKm);
                      widget.onConfirm(_selectedVehicle, fare);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Confirm Ride',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
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
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final String type = vehicle['type'] as String;
    final String icon = vehicle['icon'] as String;
    final String title = vehicle['title'] as String;
    final String eta = vehicle['eta'] as String;
    final String subtitle = vehicle['subtitle'] as String;
    final String description = vehicle['description'] as String;
    final int capacity = vehicle['capacity'] as int;
    final Color accentColor = vehicle['color'] as Color;
    final Color bgColor = vehicle['bgColor'] as Color;

    final bool isSelected = _selectedVehicle == type;
    final double fare = _resolveFare(type, widget.distanceKm);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedVehicle = type;
            });
            // Add haptic feedback if available
            // HapticFeedback.selectionClick();
          },
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [bgColor, bgColor.withValues(alpha: 0.05)],
                    )
                  : null,
              color: isSelected ? bgColor.withValues(alpha: 0.16) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? accentColor.withValues(alpha: 0.6) : _brandBorder,
                width: isSelected ? 2.5 : 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: _brandPink.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // Enhanced Vehicle Icon with Gradient Background
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(colors: [accentColor, accentColor.withValues(alpha: 0.8)])
                        : const LinearGradient(colors: [Color(0xFFFFEEF7), Colors.white]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.3)
                            : _brandPink.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      icon,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Enhanced Details Section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _brandText,
                              letterSpacing: -0.4,
                            ),
                          ),
                          // Enhanced Price Display
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(colors: [accentColor, accentColor.withValues(alpha: 0.8)])
                                  : const LinearGradient(colors: [Color(0xFFFFEEF7), Colors.white]),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? accentColor.withValues(alpha: 0.2)
                                      : _brandPink.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '₹${fare.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? Colors.white : _brandPink,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: isSelected ? accentColor : _brandMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            eta,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: isSelected ? accentColor : _brandMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: _brandMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$capacity seats',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: _brandMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: _brandMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: _brandMuted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Selection Indicator
                if (isSelected) ...[
                  const SizedBox(width: 16),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
