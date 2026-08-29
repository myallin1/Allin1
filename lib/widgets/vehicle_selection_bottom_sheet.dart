import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/fare_rates.dart';
import '../config/ride_catalog.dart';
import '../models/ride_model.dart';
import '../services/theme_service.dart';
import 'cached_cloud_image.dart';

// Maps a ride_catalog vehicle key to its slot in the Home dashboard's
// Taxi & Transportation pink icon set (taxi_1..taxi_5), so this sheet
// shows the same themed render instead of a plain unicode emoji when the
// customer has picked the Pink & White 3D icon theme. mini_truck and
// lorry share slot 5 (both are the "truck" render); emergency_manpower
// has no pink asset yet and keeps its emoji.
int? _taxiPinkSlot(String vehicleKey) {
  switch (vehicleKey) {
    case 'bike':
      return 1;
    case 'auto':
      return 2;
    case 'cab':
      return 3;
    case 'parcel':
      return 4;
    case 'mini_truck':
    case 'lorry':
      return 5;
    default:
      return null;
  }
}

// Photo Realistic theme — same photo set as bike_booking_screen.dart's
// inline map, kept in sync manually since they're two different files.
String? _taxiPhotoUrl(String vehicleKey) {
  switch (vehicleKey) {
    case 'bike':
      return 'https://images.unsplash.com/photo-1558981806-ec527fa84c39?w=200&q=80';
    case 'auto':
      return 'https://images.unsplash.com/photo-1601362840469-51e4d8d58785?w=200&q=80';
    case 'cab':
      return 'https://images.unsplash.com/photo-1533473359331-0135ef1b58bf?w=200&q=80';
    case 'parcel':
      return 'https://images.unsplash.com/photo-1595246140625-573b715d11dc?w=200&q=80';
    case 'mini_truck':
    case 'lorry':
      return 'https://images.unsplash.com/photo-1601584115197-04ecc0da31d7?w=200&q=80';
    default:
      return null;
  }
}

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
          // FIX (per Nizam's request — "vehichle select confirmation
          // pandra screen la irukurathum big ah iruku so athayum scrool
          // panni pakkama single view la paathu vehichle confirm
          // pandramari antha size um optimize panni cute pannanum"):
          // swapped the SingleChildScrollView for a plain Column so the
          // whole sheet (header + vehicle list + confirm button) fits
          // in one static view — every size/spacing below was shrunk to
          // make that fit without scrolling for a typical ride catalog.
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16, left: 18, right: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Enhanced Drag Handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

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
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          color: _brandText,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.distanceKm.toStringAsFixed(1)} km trip',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: _brandMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _brandPink.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.directions_car_rounded,
                        color: _brandPink,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Enhanced Vehicle List
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: kRideCatalog.length,
                    itemBuilder: (context, index) => _buildVehicleCard(kRideCatalog[index]),
                  ),
                ),

                const SizedBox(height: 12),

                // Premium Confirm Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_brandPink, _brandPurple],
                    ),
                    borderRadius: BorderRadius.circular(18),
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
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          'Confirm Ride',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
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

  Widget _buildVehicleCard(RideCatalogEntry vehicle) {
    final String type = vehicle.key;
    final String icon = vehicle.emoji;
    final String title = vehicle.sheetTitle;
    final String eta = vehicle.eta;
    final String subtitle = vehicle.subtitle;
    final int capacity = vehicle.capacity;
    final Color accentColor = vehicle.color;
    final Color bgColor = vehicle.bgColor;

    final bool isSelected = _selectedVehicle == type;
    final double fare = _resolveFare(type, widget.distanceKm);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedVehicle = type;
            });
            // Add haptic feedback if available
            // HapticFeedback.selectionClick();
          },
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [bgColor, bgColor.withValues(alpha: 0.05)],
                    )
                  : null,
              color: isSelected ? bgColor.withValues(alpha: 0.16) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? accentColor.withValues(alpha: 0.6) : _brandBorder,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: _brandPink.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // Enhanced Vehicle Icon with Gradient Background
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(colors: [accentColor, accentColor.withValues(alpha: 0.8)])
                        : const LinearGradient(colors: [Color(0xFFFFEEF7), Colors.white]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.3)
                            : _brandPink.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Builder(builder: (context) {
                      final iconTheme = context.watch<ThemeService>().iconThemeKey;
                      final photoUrl = _taxiPhotoUrl(type);
                      if (iconTheme == 'photo_realistic' && photoUrl != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedCloudImage(
                            photoUrl,
                            width: 28, height: 28, fit: BoxFit.cover,
                            cacheWidth: 112,
                            errorWidget: Text(icon, style: const TextStyle(fontSize: 20)),
                          ),
                        );
                      }
                      final pinkSlot = _taxiPinkSlot(type);
                      final isPink = pinkSlot != null && iconTheme == 'pink_white_3d';
                      if (isPink) {
                        return Image.asset(
                          'assets/images/pink_icons/taxi_${pinkSlot}_a.webp',
                          width: 28, height: 28, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Text(icon, style: const TextStyle(fontSize: 20)),
                        );
                      }
                      return Text(icon, style: const TextStyle(fontSize: 20));
                    }),
                  ),
                ),
                const SizedBox(width: 10),

                // Enhanced Details Section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _brandText,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          // Enhanced Price Display
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(colors: [accentColor, accentColor.withValues(alpha: 0.8)])
                                  : const LinearGradient(colors: [Color(0xFFFFEEF7), Colors.white]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? accentColor.withValues(alpha: 0.2)
                                      : _brandPink.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '₹${fare.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? Colors.white : _brandPink,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: isSelected ? accentColor : _brandMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            eta,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: isSelected ? accentColor : _brandMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.person_rounded,
                            size: 11,
                            color: _brandMuted,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$capacity seats',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: _brandMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: _brandMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Selection Indicator
                if (isSelected) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
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
