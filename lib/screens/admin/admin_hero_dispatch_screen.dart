import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_ride_dispatch_service.dart';
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
  // Separate from _isLoading above (that one's the dispatch bottom-sheet's
  // "Send Ride Request" submit spinner — a different concern). This one
  // tracks whether the FIRST online_heroes snapshot has arrived yet, so
  // the UI can tell "still loading" apart from "genuinely zero heroes
  // online right now" instead of showing "No heroes online" for a moment
  // on every screen open before the real data lands.
  bool _heroesLoading = true;

  // NEW (per Nizam's request — "ipo irukura heros list kulla oru
  // filter vaikanum, all heros and online heros nu"): 'online' keeps
  // the existing behavior (live online_heroes RTDB stream, already
  // efficient — single persistent listener, torn down while
  // backgrounded). 'all' is a ONE-TIME Firestore fetch of every
  // approved hero (not a live listener — deliberately, per Nizam's
  // explicit "database reads waste agakudathu" requirement), refreshed
  // only when this filter is selected or pull-to-refreshed, then
  // overlaid with whatever's currently in _onlineHeroes for live
  // online/offline status per card.
  String _filter = 'online';
  bool _allHeroesLoading = false;
  List<Map<String, dynamic>> _allHeroes = [];

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
          if (mounted) {
            setState(() {
              _onlineHeroes = [];
              _heroesLoading = false;
            });
          }
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

        if (mounted) {
          setState(() {
            _onlineHeroes = heroes;
            _heroesLoading = false;
          });
        }
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

  Future<void> _loadAllHeroes() async {
    setState(() => _allHeroesLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('heroes')
          .where('approvalStatus', isEqualTo: 'approved')
          .get();
      if (!mounted) return;
      setState(() {
        _allHeroes = snap.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'heroId': doc.id,
            'name': (data['captainName'] as String?) ??
                (data['name'] as String?) ??
                'Hero',
            'phone': (data['phone'] as String?) ?? '',
            'vehicleType': (data['vehicleType'] as String?) ?? 'bike',
          };
        }).toList();
        _allHeroesLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _allHeroesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load heroes: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    if (filter == 'all' && _allHeroes.isEmpty && !_allHeroesLoading) {
      unawaited(_loadAllHeroes());
    }
  }

  /// Direct dial — always available regardless of online/available
  /// status, so admin can reach any hero straight from the list or map
  /// without going through the full ride-dispatch form.
  Future<void> _callHero(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on file for this hero.')),
      );
      return;
    }
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// FIX (per Nizam's request — map markers should show name + a call
  /// button, reachable regardless of availability): the old
  /// onMarkerTap went straight into _selectHero(), which fully blocked
  /// a busy hero with just an error toast and no way to call them at
  /// all. This lightweight sheet always shows the name and a call
  /// button; "Dispatch a Ride" only appears when the hero is actually
  /// available.
  void _showHeroInfoSheet(Map<String, dynamic> hero) {
    final isAvailable = hero['isAvailable'] == true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: (isAvailable ? _green : _red).withValues(alpha: 0.2),
                  child: Text(
                    ((hero['name'] as String?) ?? 'H')[0].toUpperCase(),
                    style: TextStyle(color: isAvailable ? _green : _red),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((hero['name'] as String?) ?? 'Hero',
                          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16),),
                      Text(
                        '${hero['vehicleType'] ?? 'bike'} • ${isAvailable ? 'Available' : 'On a task'}',
                        style: TextStyle(color: isAvailable ? _green : _red, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.call_rounded, color: _green),
                  onPressed: () => _callHero(hero['phone'] as String?),
                ),
              ],
            ),
            if (isAvailable) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _pink),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _selectHero(hero);
                  },
                  child: const Text('Dispatch a Ride', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      ),
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
      _selectedHeroId = hero['heroId'] as String?;
      _selectedHeroName = hero['name'] as String?;
      _selectedHeroPhone = hero['phone'] as String?;
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
                      color: _pink.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _selectedHeroName?.isNotEmpty ?? false
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
                // FIX (per Nizam's request — "bike,car,auto,truck,
                // lorry,heros nu yellarayum admin gps valiya map
                // monitor panni call pandra option irukanum"): added
                // truck/lorry, matching the full vehicle set heroes can
                // actually register as.
                items: ['bike', 'auto', 'car', 'truck', 'lorry', 'parcel']
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
                            await AdminRideDispatchService.dispatchRideToHero(
                              customerName: _nameCtrl.text.trim(),
                              customerPhone: _phoneCtrl.text.trim(),
                              pickupAddress: _pickupCtrl.text.trim(),
                              dropAddress: _dropCtrl.text.trim(),
                              category: _selectedCategory,
                              heroId: _selectedHeroId!,
                              heroName: _selectedHeroName ?? 'Hero',
                              heroPhone: _selectedHeroPhone ?? '',
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ride sent to hero'), backgroundColor: _green),
                              );
                            }
                            _nameCtrl.clear();
                            _phoneCtrl.clear();
                            _pickupCtrl.clear();
                            _dropCtrl.clear();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                              );
                            }
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
    if (_heroesLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _pink)),
      );
    }

    // Merges the one-time "All Heroes" fetch with live online-status
    // (and, when present, GPS position) from the already-running
    // online_heroes stream — no extra reads, just an in-memory join.
    final onlineById = {
      for (final h in _onlineHeroes) h['heroId'] as String: h,
    };
    final listHeroes = _filter == 'all'
        ? _allHeroes.map((h) {
            final live = onlineById[h['heroId']];
            return <String, dynamic>{
              ...h,
              'isOnline': live != null,
              'isAvailable': live?['isAvailable'] ?? false,
              'lat': live?['lat'],
              'lng': live?['lng'],
              'distanceKm': live?['distanceKm'],
            };
          }).toList()
        : _onlineHeroes;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text('Dispatch Heroes', style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // NEW (per Nizam's request — All/Online filter): only
              // meaningfully affects the List tab below (heroes without
              // a live GPS fix can't be plotted on the Map tab, so that
              // one always shows current online_heroes regardless).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Online Heroes'),
                      selected: _filter == 'online',
                      onSelected: (_) => _setFilter('online'),
                      selectedColor: _pink.withValues(alpha: 0.25),
                      labelStyle: TextStyle(color: _filter == 'online' ? _pink : _muted, fontSize: 12),
                      backgroundColor: _card,
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('All Heroes'),
                      selected: _filter == 'all',
                      onSelected: (_) => _setFilter('all'),
                      selectedColor: _pink.withValues(alpha: 0.25),
                      labelStyle: TextStyle(color: _filter == 'all' ? _pink : _muted, fontSize: 12),
                      backgroundColor: _card,
                    ),
                    if (_filter == 'all' && _allHeroesLoading) ...[
                      const SizedBox(width: 10),
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _pink)),
                    ],
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: _pink,
                labelColor: _pink,
                unselectedLabelColor: _muted,
                tabs: const [
                  Tab(icon: Icon(Icons.list_rounded), text: 'List'),
                  Tab(icon: Icon(Icons.map_rounded), text: 'Map'),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _green.withValues(alpha: 0.4)),
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
          if (listHeroes.isEmpty)
            Center(
              child: Text(
                _filter == 'all' ? 'No approved heroes found' : 'No heroes online',
                style: const TextStyle(color: _muted),
              ),
            )
          else
            ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: listHeroes.length,
                  itemBuilder: (ctx, i) {
                    final hero = listHeroes[i];
                    final isOnline = _filter == 'all' ? (hero['isOnline'] == true) : true;
                    final isAvailable = hero['isAvailable'] == true;
                    final distanceKm = hero['distanceKm'] as double?;
                    final statusColor = !isOnline ? _muted : (isAvailable ? _green : _red);
                    return Card(
                      color: _card,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        // Only online, available heroes go straight into
                        // the ride-dispatch flow — anyone else is still
                        // fully reachable via the call button below,
                        // just not dispatchable right now.
                        onTap: isOnline ? () => _selectHero(hero) : null,
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withValues(alpha: 0.2),
                          child: Text(
                            ((hero['name'] as String?) ?? 'H')[0].toUpperCase(),
                            style: TextStyle(color: statusColor),
                          ),
                        ),
                        title: Text((hero['name'] as String?) ?? 'Hero', style: const TextStyle(color: _text)),
                        subtitle: Text(
                          distanceKm != null
                              ? '${hero['vehicleType'] ?? 'bike'} • ${distanceKm.toStringAsFixed(1)}km away'
                              : '${hero['vehicleType'] ?? 'bike'}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                        // NEW (per Nizam's request — "name ku pakkathula
                        // call button irukanum, atha thotta antha hero
                        // ku nera call poganum"): call icon always
                        // reachable, regardless of online/available
                        // status.
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                !isOnline ? 'OFFLINE' : (isAvailable ? 'AVAILABLE' : 'ON RIDE'),
                                style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.call_rounded, color: _green, size: 20),
                              onPressed: () => _callHero(hero['phone'] as String?),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          if (_onlineHeroes.isEmpty) const Center(child: Text('Loading heroes...', style: TextStyle(color: _muted))) else Container(
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
                          color: (hero['isAvailable'] as bool?) ?? false ? _green : _red,
                        );
                      }).toList(),
                      onMarkerTap: (index) => _showHeroInfoSheet(_onlineHeroes[index]),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
