import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ride_search_service.dart';
import '../../widgets/allin1_map_widget.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _pink = Color(0xFFFF4FA3);

// TODO(Phase 2): Replace with real dispatch-center / pickup coordinates once geocoding is wired up.
const LatLng _erodeCenter = LatLng(11.3410, 77.7172);

class AdminHeroDispatchScreen extends StatefulWidget {
  const AdminHeroDispatchScreen({super.key});

  @override
  State<AdminHeroDispatchScreen> createState() => _AdminHeroDispatchScreenState();
}

class _AdminHeroDispatchScreenState extends State<AdminHeroDispatchScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<Map<String, dynamic>> _onlineHeroes = [];
  LatLng? _selectedHeroLocation;
  String? _selectedHeroId;
  String? _selectedHeroName;
  String? _selectedHeroPhone;
  bool _isLoading = false;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _pickupCtrl = TextEditingController();
  final TextEditingController _dropCtrl = TextEditingController();
  String _selectedCategory = 'bike';

  late StreamSubscription<DatabaseEvent> _heroesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _listenToOnlineHeroes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _heroesSub.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Admin isn't actively viewing this screen — stop the RTDB
        // read stream to avoid wasted background reads.
        _heroesSub.cancel();
        debugPrint('[AdminHeroDispatch] Backgrounded — stopped online_heroes listener');
        break;
      case AppLifecycleState.resumed:
        // Admin is back — re-subscribe to get a fresh live stream.
        debugPrint('[AdminHeroDispatch] Resumed — restarting online_heroes listener');
        _listenToOnlineHeroes();
        break;
    }
  }

  void _listenToOnlineHeroes() {
    _heroesSub = FirebaseDatabase.instance.ref('online_heroes').onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw is! Map) {
          if (mounted) setState(() => _onlineHeroes = []);
          return;
        }

        final heroes = <Map<String, dynamic>>[];
        try {
          raw.forEach((key, value) {
            if (value is Map) {
              final lat = (value['lat'] as num?)?.toDouble();
              final lng = (value['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final distanceKm = const Distance().as(
                  LengthUnit.Kilometer,
                  _erodeCenter,
                  LatLng(lat, lng),
                );
                heroes.add({
                  'heroId': key,
                  'lat': lat,
                  'lng': lng,
                  'name': (value['name'] as String?) ?? 'Hero',
                  'vehicleType': (value['vehicleType'] as String?) ?? 'bike',
                  'isAvailable': (value['isAvailable'] as bool?) ?? true,
                  'phone': (value['phone'] as String?) ?? '',
                  'vehicleNumber': (value['vehicleNumber'] as String?) ?? '',
                  'distanceKm': distanceKm,
                });
              }
            }
          });
          heroes.sort((a, b) => (a['distanceKm'] as double).compareTo(b['distanceKm'] as double));
        } catch (e) {
          debugPrint('online_heroes parse error: $e');
        }

        if (mounted) setState(() => _onlineHeroes = heroes);
      },
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Live tracking error: $e'), backgroundColor: Colors.red),
          );
        }
      },
    );
  }

  void _selectHero(Map<String, dynamic> hero) {
    if (hero['isAvailable'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indha Hero already oru ride-la irukkaaru'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _selectedHeroId = (hero['heroId'] as String?);
      _selectedHeroName = (hero['name'] as String?);
      _selectedHeroPhone = (hero['phone'] as String?);
      _selectedHeroLocation = LatLng((hero['lat'] as num).toDouble(), (hero['lng'] as num).toDouble());
    });

    _showDispatchDialog();
  }

  void _showDispatchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _pink.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _selectedHeroName?.isNotEmpty == true
                            ? _selectedHeroName![0].toUpperCase()
                            : 'H',
                        style: const TextStyle(color: _pink, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedHeroName ?? 'Hero', style: const TextStyle(color: _text, fontWeight: FontWeight.bold)),
                        const Text('Available Now', style: TextStyle(color: _green, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (_selectedHeroPhone != null && _selectedHeroPhone!.isNotEmpty)
                    IconButton(
                      onPressed: () async {
                        final url = Uri.parse('tel:$_selectedHeroPhone');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                      icon: const Icon(Icons.call_rounded, color: _green),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 12),
              Text('Customer Details', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: _card,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Customer Phone',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: _card,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pickupCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Pickup Address',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: _card,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dropCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Drop Address',
                  labelStyle: TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: _card,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButton<String>(
                value: _selectedCategory,
                dropdownColor: _card,
                style: const TextStyle(color: Colors.white),
                isExpanded: true,
                items: ['bike', 'auto', 'car', 'parcel']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase())))
                    .toList(),
                onChanged: (v) => setSheetState(() => _selectedCategory = v!),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _pink),
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_nameCtrl.text.isEmpty ||
                              _phoneCtrl.text.isEmpty ||
                              _pickupCtrl.text.isEmpty ||
                              _dropCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Fill all fields'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          setSheetState(() => _isLoading = true);
                          try {
                            final service = RideSearchService();
                            final normalizedPhone = RideSearchService.normalizePhone(_phoneCtrl.text);
                            final rideData = {
                              'customerName': _nameCtrl.text.trim(),
                              'customerPhone': normalizedPhone,
                              'pickupAddress': _pickupCtrl.text.trim(),
                              'dropAddress': _dropCtrl.text.trim(),
                              'category': _selectedCategory,
                              'pickupLatitude': _erodeCenter.latitude,
                              'pickupLongitude': _erodeCenter.longitude,
                            };
                            final rideId = await service.createCallCenterRide(rideData);
                            if (rideId != null && _selectedHeroId != null) {
                              await service.pingHero(_selectedHeroId!, rideId, rideData);
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ride sent to hero!'), backgroundColor: Colors.green),
                                );
                              }
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                            );
                          } finally {
                            setSheetState(() => _isLoading = false);
                          }
                        },
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send Ride Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Dispatch Heroes', style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _pink,
          labelColor: _pink,
          unselectedLabelColor: _muted,
          tabs: const [
            Tab(icon: Icon(Icons.list_rounded), text: 'List'),
            Tab(icon: Icon(Icons.map_rounded), text: 'Map'),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _green.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('${_onlineHeroes.length} Online', style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _onlineHeroes.isEmpty
              ? const Center(child: Text('No heroes online', style: TextStyle(color: _muted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _onlineHeroes.length,
                  itemBuilder: (ctx, i) {
                    final hero = _onlineHeroes[i];
                    final isAvailable = hero['isAvailable'] == true;
                    final distanceKm = hero['distanceKm'] as double;
                    return Card(
                      color: _card,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: () => _selectHero(hero),
                        leading: CircleAvatar(
                          backgroundColor: isAvailable ? _green.withOpacity(0.2) : _red.withOpacity(0.2),
                          child: Text(
                            ((hero['name'] as String?) ?? 'H')[0].toUpperCase(),
                            style: TextStyle(color: isAvailable ? _green : _red),
                          ),
                        ),
                        title: Text((hero['name'] as String?) ?? 'Hero', style: const TextStyle(color: _text)),
                        subtitle: Text(
                          '${hero['vehicleType'] ?? 'bike'} - ${distanceKm.toStringAsFixed(1)}km away',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isAvailable ? _green.withOpacity(0.2) : _red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isAvailable ? 'AVAILABLE' : 'ON RIDE',
                            style: TextStyle(color: isAvailable ? _green : _red, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          _onlineHeroes.isEmpty
              ? const Center(child: Text('Loading heroes...', style: TextStyle(color: _muted)))
              : Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Allin1MapWidget(
                      center: _erodeCenter,
                      zoom: 12,
                      markers: _onlineHeroes.map((hero) {
                        return MapMarker(
                          point: LatLng((hero['lat'] as num).toDouble(), (hero['lng'] as num).toDouble()),
                          label: (hero['name'] as String?) ?? 'Hero',
                          icon: Icons.person_pin_circle_rounded,
                          color: (hero['isAvailable'] as bool?) == true ? _green : _red,
                        );
                      }).toList(),
                      onMarkerTap: (index) => _selectHero(_onlineHeroes[index]),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
