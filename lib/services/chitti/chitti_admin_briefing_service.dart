import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'chitti_role_lookup_service.dart';
import 'chitti_voice_service.dart';

class ChittiAdminBriefingService {
  ChittiAdminBriefingService._();
  static final ChittiAdminBriefingService instance = ChittiAdminBriefingService._();

  static const String _kMorningBriefingEnabledKey = 'personal_morning_briefing_enabled';
  static const String _kLastBriefingDateKey = 'last_admin_briefing_date';
  
  final FlutterTts _tts = FlutterTts();
  bool _hasSpokenThisSession = false;
  bool _isSpeaking = false;

  Future<void> speakBriefingIfFirstTimeToday() async {
    // Session lock check
    if (_hasSpokenThisSession) {
      debugPrint('[ChittiAdminBriefingService] Already checked/spoken this session. Skipping.');
      return;
    }
    _hasSpokenThisSession = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Mute/Disable Toggle check
      final enabled = prefs.getBool(_kMorningBriefingEnabledKey) ?? true;
      if (!enabled) {
        debugPrint('[ChittiAdminBriefingService] Morning briefing is disabled in settings. Skipping.');
        return;
      }

      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // Check if already spoken today
      final lastBriefing = prefs.getString(_kLastBriefingDateKey);
      if (lastBriefing == todayStr) {
        debugPrint('[ChittiAdminBriefingService] Briefing already spoken today ($todayStr). Skipping.');
        return;
      }

      debugPrint('[ChittiAdminBriefingService] Generating business briefing for $todayStr...');

      // Fetch summaries in parallel
      final results = await Future.wait([
        ChittiRoleLookupService.adminPendingApprovalsSummary(),
        ChittiRoleLookupService.adminTodayActivitySummary(),
        ChittiRoleLookupService.adminOpenBugsSummary(),
        ChittiRoleLookupService.adminOpenEnquiriesSummary(),
        ChittiRoleLookupService.adminCommunicationsSummary(),
      ]);

      final approvalsRaw = results[0];
      final activityRaw = results[1];
      final bugsRaw = results[2];
      final enquiriesRaw = results[3];
      final commsRaw = results[4];

      // Calculate diffs (What Changed)
      final prevApprovals = prefs.getInt('last_seen_approvals_count') ?? 0;
      final prevBugs = prefs.getInt('last_seen_bugs_count') ?? 0;
      final prevEnquiries = prefs.getInt('last_seen_enquiries_count') ?? 0;

      final currentApprovals = _extractNumber(approvalsRaw);
      final currentBugs = _extractNumber(bugsRaw);
      final currentEnquiries = _extractNumber(enquiriesRaw);

      // Save new counts for next diff check
      await prefs.setInt('last_seen_approvals_count', currentApprovals);
      await prefs.setInt('last_seen_bugs_count', currentBugs);
      await prefs.setInt('last_seen_enquiries_count', currentEnquiries);

      // Determine language
      final lang = prefs.getString('customer_language_code') ?? 'en';
      String briefingText = '';
      String locale = 'en-US';

      final isTamil = (lang == 'ta');
      locale = isTamil ? 'ta-IN' : 'en-US';

      // Select intro template based on time of day (Morning/Evening/Weekly Wrap)
      final hour = now.hour;
      final isMonday = (now.weekday == DateTime.monday);
      
      String intro = '';
      String closing = '';

      if (isTamil) {
        final approvalsTa = _translateSummaryToTamil(approvalsRaw, 'approvals');
        final activityTa = _translateSummaryToTamil(activityRaw, 'activity');
        final bugsTa = _translateSummaryToTamil(bugsRaw, 'bugs');
        final enquiriesTa = _translateSummaryToTamil(enquiriesRaw, 'enquiries');
        final commsTa = _translateSummaryToTamil(commsRaw, 'comms');

        // Diff text in Tamil
        String diffText = '';
        if (currentApprovals > prevApprovals) {
          final diff = currentApprovals - prevApprovals;
          diffText += "புதிதாக $diff அப்ரூவல் கோரிக்கைகள் வந்துள்ளன. ";
        }
        if (currentBugs > prevBugs) {
          final diff = currentBugs - prevBugs;
          diffText += "$diff புதிய பக் ரிப்போர்ட்டுகள் பதிவாகியுள்ளன. ";
        }
        if (currentEnquiries > prevEnquiries) {
          final diff = currentEnquiries - prevEnquiries;
          diffText += "$diff புதிய என்கொயரிகள் வந்துள்ளன. ";
        }

        if (isMonday) {
          intro = "வணக்கம் பாஸ்! ஒரு புதிய வாரத்தின் துவக்கம். இந்த வார பிசினஸ் ரிப்போர்ட் இதோ. ";
        } else if (hour >= 17) {
          intro = "மாலை வணக்கம் பாஸ்! இன்றைய மாலை நேர பிசினஸ் அறிக்கை இதோ. ";
        } else {
          intro = "காலை வணக்கம் பாஸ்! இன்றைய பிசினஸ் அறிக்கை இதோ. ";
        }

        if (diffText.isNotEmpty) {
          intro += "நீங்கள் கடைசியாகப் பார்த்ததிலிருந்து, $diffText";
        }

        if (hour >= 17) {
          closing = "இன்றைய நாள் உங்களுக்கு பயனுள்ளதாக அமைந்திருக்கும் என நம்புகிறேன். இனிய மாலை பொழுது அமையட்டும் பாஸ்! நன்றி.";
        } else {
          closing = "இன்றைய நாள் உங்களுக்கு சிறப்பாக அமையட்டும். நன்றி பாஸ்!";
        }

        briefingText = "$intro $approvalsTa $activityTa $commsTa $bugsTa $enquiriesTa $closing";
      } else {
        // Diff text in English
        String diffText = '';
        if (currentApprovals > prevApprovals) {
          final diff = currentApprovals - prevApprovals;
          diffText += "$diff new approval requests since you last checked. ";
        }
        if (currentBugs > prevBugs) {
          final diff = currentBugs - prevBugs;
          diffText += "$diff new bug reports. ";
        }
        if (currentEnquiries > prevEnquiries) {
          final diff = currentEnquiries - prevEnquiries;
          diffText += "$diff new enquiries. ";
        }

        if (isMonday) {
          intro = "Welcome to a new week, boss! Here is your weekly business digest. ";
        } else if (hour >= 17) {
          intro = "Good evening boss! Here is your end-of-day business wrap-up. ";
        } else {
          intro = "Good morning boss! Here is your executive briefing for today. ";
        }

        if (diffText.isNotEmpty) {
          intro += "Since you last checked, we have $diffText";
        }

        if (hour >= 17) {
          closing = "Hope you had a productive day. Have a relaxing evening!";
        } else {
          closing = "Have a great and productive day!";
        }

        briefingText = "$intro $approvalsRaw $activityRaw $bugsRaw $enquiriesRaw $closing";
      }

      debugPrint('[ChittiAdminBriefingService] Speaking briefing ($locale): $briefingText');

      _isSpeaking = true;
      await ChittiVoiceService.apply(_tts, locale);
      await _tts.speak(briefingText);

      // Save date only after successfully initiating speak
      await prefs.setString(_kLastBriefingDateKey, todayStr);
    } catch (e) {
      debugPrint('[ChittiAdminBriefingService] Error during briefing: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> stopBriefing() async {
    if (_isSpeaking) {
      debugPrint('[ChittiAdminBriefingService] Stopping active speech playback.');
      try {
        await _tts.stop();
      } catch (_) {}
      _isSpeaking = false;
    }
  }

  void resetSession() {
    _hasSpokenThisSession = false;
  }

  int _extractNumber(String text) {
    // Extracts the first positive integer from the raw string
    final match = RegExp(r'(\d+)').firstMatch(text);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  String _translateSummaryToTamil(String summary, String type) {
    summary = summary.trim();
    if (type == 'approvals') {
      if (summary.contains('clear')) {
        return "அப்ரூவல் க்யூ காலியா இருக்கு பாஸ். யாரும் உங்களுக்காக வெயிட் பண்ணல.";
      }
      final match = RegExp(r'Waiting for approval:\s*(.*)\.').firstMatch(summary);
      if (match != null) {
        var details = match.group(1) ?? '';
        details = details.replaceAll('heroes', 'ஹீரோக்கள்').replaceAll('hero', 'ஹீரோ');
        details = details.replaceAll('sellers', 'செல்லர்கள்').replaceAll('seller', 'செல்லர்');
        details = details.replaceAll('and', 'மற்றும்');
        return "அப்ரூவலுக்காக $details வெயிட்டிங்ல இருக்காங்க பாஸ்.";
      }
    } else if (type == 'activity') {
      if (summary.contains('No orders have come in today yet') || summary.contains('No orders')) {
        return "இன்னைக்கு இன்னும் ஆர்டர்கள் எதுவும் வரல பாஸ்.";
      }
      final match = RegExp(r'(\d+)\s*orders? today,\s*(\d+)\s*still in progress').firstMatch(summary);
      if (match != null) {
        final total = match.group(1);
        final open = match.group(2);
        if (open == "0") {
          return "இன்னைக்கு $total ஆர்டர்கள் வந்திருக்கு, எல்லாமே கம்ப்ளீட் ஆயிடுச்சு பாஸ்.";
        }
        return "இன்னைக்கு $total ஆர்டர்கள் வந்திருக்கு, அதுல $open ஆர்டர்கள் இன்னும் ப்ராக்ரெஸ்ல இருக்கு பாஸ்.";
      }
    } else if (type == 'bugs') {
      if (summary.contains('No open bug reports') || summary.contains('No open bugs')) {
        return "பக்ஸ் எதுவும் ரிப்போர்ட் ஆகல பாஸ். ஆப் கிளீனா ரன் ஆகுது.";
      }
      final match = RegExp(r'(\d+)\s*open bug reports?').firstMatch(summary);
      if (match != null) {
        final count = match.group(1);
        final highMatch = RegExp(r'(\d+)\s*marked high severity').firstMatch(summary);
        if (highMatch != null) {
          final high = highMatch.group(1);
          return "இப்போ $count ஓபன் பக் ரிப்போர்ட்டுகள் இருக்கு, அதுல $high பக்ஸ் ரொம்ப முக்கியமானது பாஸ்.";
        }
        return "இப்போ $count ஓபன் பக் ரிப்போர்ட்டுகள் இருக்கு பாஸ்.";
      }
    } else if (type == 'enquiries') {
      if (summary.contains('No customer enquiries are waiting') || summary.contains('No customer enquiries')) {
        return "வாடிக்கையாளர் என்கொயரிகள் எதுவும் பெண்டிங் இல்லை பாஸ்.";
      }
      final match = RegExp(r'(\d+|100 or more)\s*customers? waiting for a price').firstMatch(summary);
      if (match != null) {
        final count = match.group(1);
        return "இப்போ $count வாடிக்கையாளர்கள் விலை விபரம் கேட்டு உங்களுக்காக பெண்டிங்ல இருக்காங்க பாஸ்.";
      }
    } else if (type == 'comms') {
      if (summary.contains('No recent communications') || summary.contains('unavailable')) {
        return "";
      }
      final smsMatch = RegExp(r'(\d+)\s*recent SMS').firstMatch(summary);
      final callMatch = RegExp(r'(\d+)\s*call activity').firstMatch(summary);
      final parts = <String>[];
      if (callMatch != null) {
        parts.add('${callMatch.group(1)} அழைப்புப் பதிவுகள் உள்ளன');
      }
      if (smsMatch != null) {
        parts.add('${smsMatch.group(1)} புதிய SMS செய்திகள் வந்துள்ளன');
      }
      if (parts.isNotEmpty) {
        return "கம்யூனிகேஷன்ஸ் நிலவரம்: ${parts.join(" மற்றும் ")} பாஸ். ";
      }
    }
    return summary;
  }
}
