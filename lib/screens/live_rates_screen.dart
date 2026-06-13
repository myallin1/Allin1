import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';

class LiveRatesScreen extends StatelessWidget {
  const LiveRatesScreen({super.key});

  static Future<List<LiveRateItem>> fetchLiveRates() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return const <LiveRateItem>[
      LiveRateItem(
        title: '22K Gold',
        price: 'Rs. 6,780/g',
        icon: Icons.workspace_premium_rounded,
        iconColor: Color(0xFFE8B441),
      ),
      LiveRateItem(
        title: '24K Gold',
        price: 'Rs. 7,396/g',
        icon: Icons.diamond_rounded,
        iconColor: Color(0xFFF5C44D),
      ),
      LiveRateItem(
        title: 'Silver',
        price: 'Rs. 89,400/kg',
        icon: Icons.blur_on_rounded,
        iconColor: Color(0xFFB6B9C6),
      ),
      LiveRateItem(
        title: 'Petrol',
        price: 'Rs. 102.46/L',
        icon: Icons.local_gas_station_rounded,
        iconColor: Color(0xFFFF5C93),
      ),
      LiveRateItem(
        title: 'Diesel',
        price: 'Rs. 94.08/L',
        icon: Icons.fire_truck_rounded,
        iconColor: Color(0xFFB43CFF),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final localization = context.watch<LocalizationService>();
    const brandGradient = LinearGradient(
      colors: <Color>[
        Color(0xFFFF4FA3),
        Color(0xFFFF73C0),
        Color(0xFFB21FFF),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return ColoredBox(
      color: Colors.white,
      child: FutureBuilder<List<LiveRateItem>>(
        future: fetchLiveRates(),
        builder: (context, snapshot) {
          final rates = snapshot.data ?? const <LiveRateItem>[];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: brandGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFFF4FA3).withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        localization.t('live_rates_title'),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        localization.t('live_rates_subtitle'),
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (!snapshot.hasData)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF4FA3),
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rates.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.72,
                    ),
                    itemBuilder: (context, index) {
                      final item = rates[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0x55FF5CA8),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: const Color(0xFFFF4FA3)
                                  .withValues(alpha: 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: brandGradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                item.icon,
                                color: item.iconColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF5A1740),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              localization.t('today_price_label'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansTamil(
                                color: const Color(0xFFFF4FA3),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.price,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFB21FFF),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LiveRateItem {
  const LiveRateItem({
    required this.title,
    required this.price,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String price;
  final IconData icon;
  final Color iconColor;
}
