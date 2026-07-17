import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

const Color _drawerPink = Color(0xFFFF4FA3);
const Color _drawerPinkSoft = Color(0xFFFFA8CF);
const Color _drawerWhite = Color(0xFFFFFFFF);
const Color _drawerBorder = Color(0x33FF4FA3);

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    required this.user,
    required this.displayName,
    required this.phoneNumber,
    required this.photoUrl,
    required this.onLoginTap,
    required this.onMyProfileTap,
    required this.onRideHistoryTap,
    required this.onWalletTap,
    required this.onPaymentMethodsTap,
    required this.onNotificationsTap,
    required this.onLanguageTap,
    required this.onDownloadMobileAppTap,
    required this.onSavedAddressesTap,
    required this.onHelpSupportTap,
    required this.onSettingsTap,
    required this.onLogoutTap,
    super.key,
  });

  final User? user;
  final String displayName;
  final String phoneNumber;
  final String photoUrl;
  final VoidCallback onLoginTap;
  final VoidCallback onMyProfileTap;
  final VoidCallback onRideHistoryTap;
  final VoidCallback onWalletTap;
  final VoidCallback onPaymentMethodsTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onLanguageTap;
  final VoidCallback onDownloadMobileAppTap;
  final VoidCallback onSavedAddressesTap;
  final VoidCallback onHelpSupportTap;
  final VoidCallback onSettingsTap;
  final Future<void> Function() onLogoutTap;

  bool get _isLoggedIn => user != null && !user!.isAnonymous;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width * 0.75;
    final horizontalPadding = media.size.width * 0.05;
    final headerSpacing = media.size.width * 0.03;
    final titleSize = (media.size.width * 0.048).clamp(16.0, 20.0);
    final subtitleSize = (media.size.width * 0.033).clamp(11.0, 14.0);

    return Drawer(
      width: width,
      backgroundColor: _drawerWhite,
      elevation: 8,
      child: SafeArea(
        child: ColoredBox(
          color: _drawerWhite,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  media.size.height * 0.018,
                  horizontalPadding,
                  media.size.height * 0.01,
                ),
                child: _isLoggedIn
                    ? _LoggedInHeader(
                        user: user!,
                        displayName: displayName,
                        phoneNumber: phoneNumber,
                        photoUrl: photoUrl,
                        titleSize: titleSize,
                        subtitleSize: subtitleSize,
                        headerSpacing: headerSpacing,
                      )
                    : _GuestHeader(
                        titleSize: titleSize,
                        subtitleSize: subtitleSize,
                        headerSpacing: headerSpacing,
                        onLoginTap: () {
                          Navigator.of(context).pop();
                          onLoginTap();
                        },
                      ),
              ),
              const Divider(height: 1, color: _drawerBorder),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding * 0.55,
                    vertical: media.size.height * 0.012,
                  ),
                  children: [
                    _DrawerTile(
                      icon: Icons.person_rounded,
                      label: 'My Profile',
                      onTap: () {
                        Navigator.of(context).pop();
                        onMyProfileTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.history_rounded,
                      label: 'My Rides',
                      onTap: () {
                        Navigator.of(context).pop();
                        onRideHistoryTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Wallet',
                      onTap: () {
                        Navigator.of(context).pop();
                        onWalletTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.payment_rounded,
                      label: 'Payment Methods',
                      onTap: () {
                        Navigator.of(context).pop();
                        onPaymentMethodsTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.notifications_rounded,
                      label: 'Notifications',
                      onTap: () {
                        Navigator.of(context).pop();
                        onNotificationsTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.translate_rounded,
                      label: 'Change Language',
                      onTap: () {
                        Navigator.of(context).pop();
                        onLanguageTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.download_rounded,
                      label: 'Download Mobile App',
                      onTap: () {
                        Navigator.of(context).pop();
                        onDownloadMobileAppTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.location_on_rounded,
                      label: 'Saved Addresses',
                      onTap: () {
                        Navigator.of(context).pop();
                        onSavedAddressesTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.help_rounded,
                      label: 'Help & Support',
                      onTap: () {
                        Navigator.of(context).pop();
                        onHelpSupportTap();
                      },
                    ),
                    _DrawerTile(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      onTap: () {
                        Navigator.of(context).pop();
                        onSettingsTap();
                      },
                    ),
                    if (_isLoggedIn)
                      _DrawerTile(
                        icon: Icons.update_rounded,
                        label: 'Check for Updates',
                        onTap: () async {
                          Navigator.of(context).pop();
                          if (kIsWeb) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Open Settings → Check for Updates to refresh the app',
                                ),
                                backgroundColor: Color(0xFFFF4FA3),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            final targetUri = Uri.parse(
                              UpdateService().fallbackApkUrl('customer'),
                            );
                            final launched = await launchUrl(
                              targetUri,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!launched) {
                              onDownloadMobileAppTap();
                            }
                          }
                        },
                      ),
                    if (_isLoggedIn)
                      _DrawerTile(
                        icon: Icons.logout_rounded,
                        label: 'Sign Out / Logout',
                        onTap: () async {
                          Navigator.of(context).pop();
                          await onLogoutTap();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<User?>('user', user));
    properties.add(StringProperty('displayName', displayName));
    properties.add(StringProperty('phoneNumber', phoneNumber));
    properties.add(StringProperty('photoUrl', photoUrl));
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onLoginTap', onLoginTap));
    properties.add(
      ObjectFlagProperty<VoidCallback>.has('onMyProfileTap', onMyProfileTap),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has(
        'onRideHistoryTap',
        onRideHistoryTap,
      ),
    );
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onWalletTap', onWalletTap));
    properties.add(
      ObjectFlagProperty<VoidCallback>.has(
        'onPaymentMethodsTap',
        onPaymentMethodsTap,
      ),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has(
        'onNotificationsTap',
        onNotificationsTap,
      ),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has('onLanguageTap', onLanguageTap),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has(
        'onDownloadMobileAppTap',
        onDownloadMobileAppTap,
      ),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has(
        'onSavedAddressesTap',
        onSavedAddressesTap,
      ),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has(
        'onHelpSupportTap',
        onHelpSupportTap,
      ),
    );
    properties.add(
      ObjectFlagProperty<VoidCallback>.has('onSettingsTap', onSettingsTap),
    );
    properties.add(
      ObjectFlagProperty<Future<dynamic> Function()>.has(
        'onLogoutTap',
        onLogoutTap,
      ),
    );
  }
}

class _GuestHeader extends StatelessWidget {
  const _GuestHeader({
    required this.titleSize,
    required this.subtitleSize,
    required this.headerSpacing,
    required this.onLoginTap,
  });

  final double titleSize;
  final double subtitleSize;
  final double headerSpacing;
  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF4FA3),
            Color(0xFFFF72B8),
            Color(0xFFFFAACF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _drawerWhite.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2EFF4FA3),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: _drawerWhite,
              shape: BoxShape.circle,
              border: Border.all(color: _drawerWhite.withValues(alpha: 0.7)),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: _drawerPink,
              size: 30,
            ),
          ),
          SizedBox(height: headerSpacing),
          Text(
            'Welcome to NJ Tech',
            style: GoogleFonts.outfit(
              color: _drawerWhite,
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'MyAllin1 Super App',
            style: GoogleFonts.outfit(
              color: _drawerWhite,
              fontSize: subtitleSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Login once you are ready to book rides, place orders, and manage your wallet.',
            style: GoogleFonts.outfit(
              color: _drawerWhite.withValues(alpha: 0.92),
              fontSize: subtitleSize,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onLoginTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: _drawerWhite,
                foregroundColor: _drawerPink,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Login / Sign Up',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: subtitleSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('titleSize', titleSize));
    properties.add(DoubleProperty('subtitleSize', subtitleSize));
    properties.add(DoubleProperty('headerSpacing', headerSpacing));
    properties
        .add(ObjectFlagProperty<VoidCallback>.has('onLoginTap', onLoginTap));
  }
}

class _LoggedInHeader extends StatelessWidget {
  const _LoggedInHeader({
    required this.user,
    required this.displayName,
    required this.phoneNumber,
    required this.photoUrl,
    required this.titleSize,
    required this.subtitleSize,
    required this.headerSpacing,
  });

  final User user;
  final String displayName;
  final String phoneNumber;
  final String photoUrl;
  final double titleSize;
  final double subtitleSize;
  final double headerSpacing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF4FA3),
            Color(0xFFFF72B8),
            Color(0xFFFFAACF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _drawerWhite.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2EFF4FA3),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: _drawerWhite,
            backgroundImage:
                photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                    style: GoogleFonts.outfit(
                      color: _drawerPink,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          SizedBox(width: headerSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: _drawerWhite,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  phoneNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: _drawerWhite.withValues(alpha: 0.92),
                    fontSize: subtitleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<User>('user', user));
    properties.add(StringProperty('displayName', displayName));
    properties.add(StringProperty('phoneNumber', phoneNumber));
    properties.add(StringProperty('photoUrl', photoUrl));
    properties.add(DoubleProperty('titleSize', titleSize));
    properties.add(DoubleProperty('subtitleSize', subtitleSize));
    properties.add(DoubleProperty('headerSpacing', headerSpacing));
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final fontSize = (media.size.width * 0.038).clamp(13.0, 16.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        tileColor: _drawerWhite.withValues(alpha: 0.9),
        contentPadding: EdgeInsets.symmetric(
          horizontal: media.size.width * 0.03,
          vertical: media.size.height * 0.002,
        ),
        leading: Icon(icon, color: _drawerPink, size: fontSize + 6),
        title: Text(
          label,
          style: GoogleFonts.outfit(
            color: _drawerPink,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: _drawerPink,
          size: 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _drawerBorder),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(StringProperty('label', label));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
