// ================================================================
// admin_whatsapp_studio_screen.dart — WhatsApp Web, Chitti Chat Assist & Market Intelligence
// ================================================================
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../services/whatsapp/mobile_market_intelligence_service.dart';
import '../../services/whatsapp/whatsapp_broadcast_service.dart';
import 'admin_tabbed_browser_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _surface = Color(0xFF1B1B2C);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _purple = Color(0xFFB21FFF);
const Color _accent = Color(0xFF6C63FF);
const Color _green = Color(0xFF25D366); // WhatsApp Green
const Color _amber = Color(0xFFFFB020);
const Color _red = Color(0xFFE05555);

class AdminWhatsAppStudioScreen extends StatefulWidget {
  const AdminWhatsAppStudioScreen({super.key});

  @override
  State<AdminWhatsAppStudioScreen> createState() =>
      _AdminWhatsAppStudioScreenState();
}

class _AdminWhatsAppStudioScreenState extends State<AdminWhatsAppStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Tab 1: WhatsApp Web Controller ───────────────────────────
  WebViewController? _webViewController;
  bool _isWebLoading = true;
  bool _useDesktopMode = true;

  // Desktop User Agent to ensure WhatsApp Web loads QR instead of mobile redirect
  static const String _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  // ── Tab 2: Chitti Chat Assist & Order Generator ───────────────
  final TextEditingController _chatMessageCtrl = TextEditingController();
  String _extractedName = '';
  String _extractedPhone = '';
  String _extractedServiceType = 'electronics_service';
  String _extractedProblem = '';
  double _extractedEstPrice = 0.0;
  bool _isParsingChat = false;
  bool _isCreatingOrder = false;
  String? _orderCreationResult;

  // ── Tab 3: Bulk Video Broadcaster ────────────────────────────
  final TextEditingController _broadcastMsgCtrl = TextEditingController();
  final TextEditingController _broadcastVideoUrlCtrl = TextEditingController();
  final TextEditingController _broadcastNumbersCtrl = TextEditingController();
  List<BroadcastRecipient> _recipientsList = [];
  bool _isBroadcasting = false;
  int _broadcastSentCount = 0;

  // ── Tab 4: Market Intelligence Parser ────────────────────────
  final TextEditingController _dealerTextCtrl = TextEditingController();
  final TextEditingController _dealerNameCtrl = TextEditingController();
  final TextEditingController _marketSearchCtrl = TextEditingController();
  List<MobileMarketEntry> _parsedEntries = [];
  bool _isSavingMarketData = false;
  int _savedMarketCount = 0;
  var _marketSummaryData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initWebView();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatMessageCtrl.dispose();
    _broadcastMsgCtrl.dispose();
    _broadcastVideoUrlCtrl.dispose();
    _broadcastNumbersCtrl.dispose();
    _dealerTextCtrl.dispose();
    _dealerNameCtrl.dispose();
    _marketSearchCtrl.dispose();
    super.dispose();
  }

  void _initWebView() {
    if (kIsWeb) {
      _isWebLoading = false;
      return;
    }

    final controller = WebViewController();
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setUserAgent(_useDesktopMode ? _desktopUA : null);

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => setState(() => _isWebLoading = true),
        onPageFinished: (_) => setState(() => _isWebLoading = false),
      ),
    );

    controller.loadRequest(Uri.parse('https://web.whatsapp.com'));
    _webViewController = controller;
  }

  // ── Chat Copilot Parser ──────────────────────────────────────
  void _parseCustomerChatMessage() {
    final text = _chatMessageCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _isParsingChat = true);

    // Extract Phone
    final phoneMatch = RegExp(r'(?:\+91|91|0)?[6-9][0-9]{9}').firstMatch(text);
    _extractedPhone = phoneMatch != null
        ? WhatsAppBroadcastService.formatPhoneNumber(phoneMatch.group(0)!)
        : '';

    // Extract Name
    final nameMatch = RegExp(
      r'(?:name|i am|from|caller|customer)\s*[:=-]?\s*([a-zA-Z\s]{2,25})',
      caseSensitive: false,
    ).firstMatch(text);
    _extractedName = nameMatch?.group(1)?.trim() ?? '';

    // Detect Service Type
    final lower = text.toLowerCase();
    if (lower.contains('ride') || lower.contains('taxi') || lower.contains('bike') || lower.contains('auto') || lower.contains('pickup')) {
      _extractedServiceType = 'hero_booking';
    } else if (lower.contains('food') || lower.contains('hotel') || lower.contains('biriyani') || lower.contains('tea')) {
      _extractedServiceType = 'custom_food';
    } else if (lower.contains('grocery') || lower.contains('vegetable') || lower.contains('dmart')) {
      _extractedServiceType = 'grocery';
    } else {
      _extractedServiceType = 'electronics_service';
    }

    // Extract Price if mentioned
    final priceMatch = RegExp(r'(?:₹|rs\.?|rate)\s*([0-9]{2,6})', caseSensitive: false).firstMatch(text);
    if (priceMatch != null) {
      _extractedEstPrice = double.tryParse(priceMatch.group(1)!) ?? 0.0;
    }

    _extractedProblem = text;
    setState(() => _isParsingChat = false);
  }

  Future<void> _createServiceRequestFromChat() async {
    if (_extractedProblem.isEmpty) {
      _showSnack('Please parse a chat message first.', isError: true);
      return;
    }

    setState(() {
      _isCreatingOrder = true;
      _orderCreationResult = null;
    });

    try {
      final col = FirebaseFirestore.instance.collection('service_requests');
      final docRef = col.doc();

      final data = {
        'id': docRef.id,
        'requestType': _extractedServiceType,
        'customerName': _extractedName.isEmpty ? 'WhatsApp Customer' : _extractedName,
        'customerPhone': _extractedPhone.isEmpty ? '+919597879191' : _extractedPhone,
        'status': 'pending',
        'problem': _extractedProblem,
        'estimatedAmount': _extractedEstPrice,
        'source': 'whatsapp_chitti_studio',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'details': {
          'source': 'whatsapp',
          'notes': _extractedProblem,
        },
      };

      await docRef.set(data);

      setState(() {
        _isCreatingOrder = false;
        _orderCreationResult = 'Order #${docRef.id.substring(0, 6).toUpperCase()} created in Firestore successfully!';
      });
      _showSnack('Service Request created successfully!');
    } catch (e) {
      setState(() {
        _isCreatingOrder = false;
        _orderCreationResult = 'Error creating order: $e';
      });
      _showSnack('Failed to create order: $e', isError: true);
    }
  }

  void _sendReplyOnWhatsApp() {
    if (_extractedPhone.isEmpty) {
      _showSnack('No customer phone number detected.', isError: true);
      return;
    }
    final reply = 'வணக்கம் ${_extractedName.isNotEmpty ? _extractedName : ''}! NJ Tech / Allin1 Super App. '
        'உங்கள் கோரிக்கை ஏற்றுக்கொள்ளப்பட்டது. எங்கள் குழு விரைவில் உங்களை தொடர்பு கொள்ளும். '
        'நன்றி!';
    unawaited(WhatsAppBroadcastService.sendSingleMessage(
      phoneNumber: _extractedPhone,
      message: reply,
    ));
  }

  // ── Broadcaster ──────────────────────────────────────────────
  void _updateRecipientsList() {
    final parsed = WhatsAppBroadcastService.parseNumbers(_broadcastNumbersCtrl.text);
    setState(() => _recipientsList = parsed);
  }

  Future<void> _sendNextBroadcastItem(int index) async {
    if (index >= _recipientsList.length) {
      setState(() => _isBroadcasting = false);
      _showSnack('Broadcast complete! Sent $_broadcastSentCount messages.');
      return;
    }

    final item = _recipientsList[index];
    final success = await WhatsAppBroadcastService.sendSingleMessage(
      phoneNumber: item.phoneNumber,
      message: _broadcastMsgCtrl.text.trim(),
      videoUrl: _broadcastVideoUrlCtrl.text.trim(),
    );

    setState(() {
      _recipientsList[index] = item.copyWith(sent: success);
      if (success) _broadcastSentCount++;
    });
  }

  // ── Market Parser ────────────────────────────────────────────
  void _parseDealerText() {
    final text = _dealerTextCtrl.text.trim();
    if (text.isEmpty) return;

    final parsed = MobileMarketIntelligenceService.parseDealerPost(
      text,
      dealerName: _dealerNameCtrl.text.trim().isEmpty ? null : _dealerNameCtrl.text.trim(),
    );

    setState(() {
      _parsedEntries = parsed;
      _savedMarketCount = 0;
    });
  }

  Future<void> _saveParsedMarketRates() async {
    if (_parsedEntries.isEmpty) return;

    setState(() => _isSavingMarketData = true);
    final count = await MobileMarketIntelligenceService.saveEntries(_parsedEntries);

    setState(() {
      _isSavingMarketData = false;
      _savedMarketCount = count;
    });
    _showSnack('$count mobile market rates saved to Firestore!');
  }

  Future<void> _searchMarketPrice() async {
    final q = _marketSearchCtrl.text.trim();
    if (q.isEmpty) return;

    final summary = await MobileMarketIntelligenceService.getMarketSummary(q);
    setState(() => _marketSummaryData = summary);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _text)),
        backgroundColor: isError ? _red : _surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isError ? _red : _green),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _green.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.chat_rounded, color: _green, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'Chitti WhatsApp & Market Studio',
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: _green,
          indicatorWeight: 3,
          labelColor: _green,
          unselectedLabelColor: _muted,
          labelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(icon: Icon(Icons.web_rounded), text: 'WhatsApp Web'),
            Tab(icon: Icon(Icons.smart_toy_rounded), text: 'Chitti Chat Assist'),
            Tab(icon: Icon(Icons.send_rounded), text: 'Bulk Outreach'),
            Tab(icon: Icon(Icons.phone_android_rounded), text: 'Market Nilavaram'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWhatsAppWebTab(),
          _buildChittiChatAssistTab(),
          _buildBulkOutreachTab(),
          _buildMarketIntelligenceTab(),
        ],
      ),
    );
  }

  // ── Tab 1: WhatsApp Web View ──────────────────────────────────
  Widget _buildWhatsAppWebTab() {
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: _green.withValues(alpha: 0.3), width: 2),
                ),
                child: const Icon(Icons.chat_rounded, color: _green, size: 48),
              ),
              const SizedBox(height: 20),
              Text(
                'WhatsApp Web Hub',
                style: GoogleFonts.outfit(color: _text, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Launch WhatsApp Web in a separate tab or use the In-App Browser for full multi-tasking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => unawaited(launchUrl(
                  Uri.parse('https://web.whatsapp.com'),
                  mode: LaunchMode.externalApplication,
                )),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open WhatsApp Web in New Tab'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => unawaited(AdminTabbedBrowserScreen.openInNewTab(
                  context,
                  'https://web.whatsapp.com',
                  title: 'WhatsApp Web',
                )),
                icon: const Icon(Icons.tab_rounded),
                label: const Text('Open in Admin Multi-Tab Browser'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        if (_webViewController != null)
          WebViewWidget(controller: _webViewController!),
        if (_isWebLoading)
          const Center(
            child: CircularProgressIndicator(color: _green),
          ),
      ],
    );
  }

  // ── Tab 2: Chitti Chat Assist & Order Creator ─────────────────
  Widget _buildChittiChatAssistTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: 'Incoming WhatsApp Chat Parser',
            icon: Icons.chat_bubble_outline_rounded,
            color: _green,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste customer WhatsApp message (voice transcription or text). Chitti will extract details and generate a live order.',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _chatMessageCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. "Hi NJ Tech, my name is Karthik 9876543210. My iPhone 11 display is broken. Please pick it up today."',
                    hintStyle: const TextStyle(color: _muted, fontSize: 12),
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _parseCustomerChatMessage,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Extract & Analyze with Chitti'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: () => _chatMessageCtrl.clear(),
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(foregroundColor: _muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_extractedProblem.isNotEmpty) ...[
            _buildCard(
              title: 'Extracted Order Details',
              icon: Icons.assignment_turned_in_rounded,
              color: _accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Customer Name', _extractedName.isEmpty ? 'Unknown' : _extractedName),
                  _buildDetailRow('Phone Number', _extractedPhone.isEmpty ? 'Not detected' : _extractedPhone),
                  _buildDetailRow('Service Category', _extractedServiceType.toUpperCase()),
                  if (_extractedEstPrice > 0)
                    _buildDetailRow('Estimated Amount', '₹${_extractedEstPrice.toInt()}'),
                  const Divider(color: _border, height: 20),
                  const Text('Problem / Notes:', style: TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_extractedProblem, style: const TextStyle(color: _text, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isCreatingOrder ? null : _createServiceRequestFromChat,
                          icon: _isCreatingOrder
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.add_task_rounded, size: 16),
                          label: Text(_isCreatingOrder ? 'Creating...' : '1-Tap Create Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _sendReplyOnWhatsApp,
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Reply on WhatsApp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _card,
                          foregroundColor: _green,
                          side: const BorderSide(color: _green),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  if (_orderCreationResult != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _green.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _orderCreationResult!,
                        style: const TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 3: Bulk Outreach Broadcaster ─────────────────────────
  Widget _buildBulkOutreachTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: 'Compose Broadcast Outreach',
            icon: Icons.campaign_rounded,
            color: _amber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Message Text (Tamil / English)', style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: _broadcastMsgCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'வணக்கம்! NJ Tech Diwali Offers: Display replacement starts ₹899 with 6-month warranty.',
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Optional Video / Offer Link (Cloudinary / YouTube / MP4)', style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: _broadcastVideoUrlCtrl,
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://res.cloudinary.com/.../njtech_promo.mp4',
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Recipient Numbers (Paste comma or newline separated)', style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: _broadcastNumbersCtrl,
                  maxLines: 4,
                  onChanged: (_) => _updateRecipientsList(),
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '9876543210\n9842112233\nKarthik: 9597879191',
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_recipientsList.length} Contacts Parsed',
                      style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
                    ),
                    ElevatedButton.icon(
                      onPressed: _recipientsList.isEmpty ? null : () => _sendNextBroadcastItem(0),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Start Dispatch'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_recipientsList.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCard(
              title: 'Recipients Queue (${_recipientsList.length})',
              icon: Icons.format_list_numbered_rounded,
              color: _accent,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recipientsList.length,
                separatorBuilder: (_, __) => const Divider(color: _border, height: 1),
                itemBuilder: (context, i) {
                  final item = _recipientsList[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.name ?? item.phoneNumber, style: const TextStyle(color: _text, fontWeight: FontWeight.w600)),
                    subtitle: Text(item.phoneNumber, style: const TextStyle(color: _muted, fontSize: 11)),
                    trailing: item.sent
                        ? const Icon(Icons.check_circle_rounded, color: _green, size: 18)
                        : IconButton(
                            icon: const Icon(Icons.send_rounded, color: _accent, size: 16),
                            onPressed: () => _sendNextBroadcastItem(i),
                          ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 4: Market Intelligence Parser ─────────────────────────
  Widget _buildMarketIntelligenceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            title: 'Dealer Group 2nd Hand Mobile Parser',
            icon: Icons.phone_android_rounded,
            color: _purple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste dealer group broadcast text. Chitti parses Brand, Model, Storage, BH%, Condition & Price automatically.',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dealerNameCtrl,
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Dealer / Source Name (optional, e.g. Erode Mobiles Group)',
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dealerTextCtrl,
                  maxLines: 5,
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'iPhone 13 128GB Starlight 87% BH ₹34,500\nOnePlus 11R 8/128 Black box bill ₹23,000\nRedmi Note 13 Pro 8/256 Seal Pack ₹18,500',
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _parseDealerText,
                      icon: const Icon(Icons.psychology_rounded, size: 16),
                      label: const Text('Parse Deals'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (_parsedEntries.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isSavingMarketData ? null : _saveParsedMarketRates,
                        icon: _isSavingMarketData
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_upload_rounded, size: 16),
                        label: Text(_isSavingMarketData ? 'Saving...' : 'Save ${_parsedEntries.length} to Market DB'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_parsedEntries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCard(
              title: 'Parsed Market Rates (${_parsedEntries.length} Items)',
              icon: Icons.insights_rounded,
              color: _accent,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _parsedEntries.length,
                separatorBuilder: (_, __) => const Divider(color: _border, height: 1),
                itemBuilder: (context, i) {
                  final entry = _parsedEntries[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${entry.brand} ${entry.model}', style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('₹${entry.price.toInt()}', style: const TextStyle(color: _green, fontWeight: FontWeight.w800, fontSize: 14)),
                      ],
                    ),
                    subtitle: Text(
                      [
                        if (entry.storage != null) entry.storage,
                        if (entry.batteryHealth != null) 'BH ${entry.batteryHealth}%',
                        entry.condition,
                      ].join(' • '),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildCard(
            title: 'Live Market Query & Rate Check',
            icon: Icons.search_rounded,
            color: _amber,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _marketSearchCtrl,
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search model e.g. "iPhone 13", "OnePlus 11R"',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded, color: _amber),
                      onPressed: _searchMarketPrice,
                    ),
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                  ),
                ),
                if (_marketSummaryData != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _amber.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Market Analysis (${_marketSummaryData.totalDeals} listings)', style: GoogleFonts.outfit(color: _amber, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _buildDetailRow('Lowest Market Rate', '₹${_marketSummaryData.minPrice.toInt()}'),
                        _buildDetailRow('Average Market Rate', '₹${_marketSummaryData.averagePrice.toInt()}'),
                        _buildDetailRow('NJ Tech Selling Price (with margin)', '₹${_marketSummaryData.recommendedSellingPrice.toInt()}'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(color: _border, height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
          Text(value, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }
}
