import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService extends ChangeNotifier {
  LocalizationService({String initialLanguage = 'en'})
      : _languageCode = initialLanguage {
    unawaited(_loadSavedLanguage());
  }

  static const String _prefsKey = 'customer_language_code';

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'app_title': 'my allin1',
      'greeting': 'Hello',
      'what_need_today': 'What do you need today?',
      'bike_taxi_title': 'Bike Taxi',
      'bike_taxi_subtitle': 'Fast rides in Erode',
      'food_delivery_title': 'Food Delivery',
      'food_delivery_subtitle': '16th Road specials',
      'grocery_title': 'Grocery',
      'grocery_subtitle': 'Fresh and fast',
      'tech_store_title': 'Tech Store',
      'tech_store_subtitle': 'NJ TECH gadgets',
      'custom_order_title': 'Custom Order',
      'custom_order_subtitle': 'Ask for special service',
      'broadband_title': 'Broadband / WiFi',
      'broadband_subtitle': 'Manage your internet service',
      'mobile_puncture_title': 'Mobile Puncture',
      'mobile_puncture_subtitle': 'Fast puncture repair',
      'pharmacy_title': 'Pharmacy',
      'pharmacy_subtitle': 'Medicines delivered',
      'book_puncture': 'Book for Puncture?',
      'call_now': 'Call Now',
      'later': 'Later',
      'service_coming_soon': 'Launching soon!',
      'language_label': 'Language',
      'home_label': 'Home',
      'chat_label': 'Live Rates',
      'rides_label': 'Play Zone',
      'account_label': 'Account',
      'my_rides_label': 'My Rides',
      'live_rates_label': 'Live Rates',
      'play_zone_label': 'Play Zone',
      'live_label': 'Live',
      'erode_label': 'Erode, Tamil Nadu',
      'live_rates_title': 'Live Rates',
      'live_rates_subtitle':
          'Gold, silver and fuel prices in one quick glance for Erode.',
      'today_price_label': "Today's Price",
      'play_zone_title': 'Play Zone',
      'play_zone_subtitle':
          'Solve the 3x3 NJ TECH puzzle and beat your best time.',
      'sliding_puzzle_title': 'Sliding Puzzle Game',
      'moves_label': 'Moves',
      'time_label': 'Time',
      'reset_label': 'Reset',
      'play_again_label': 'Play Again',
      'puzzle_instruction':
          'Align the NJ TECH and Erode pattern pieces perfectly.',
      'solved_title': 'You solved it!',
      'solved_message_intro': 'Brilliant moves!',
      'bike_label': 'Bike',
      'auto_label': 'Auto',
      'cab_label': 'Cab',
      'parcel_label': 'Parcel',
      'where_to_go_hint': 'Where do you want to go?',
      'choose_vehicle_label': 'Choose Vehicle',
      'distance_label': 'Distance',
      'eta_label': 'ETA',
      'choose_destination_title': 'Choose destination',
      'update_pickup_title': 'Update pickup',
      'drag_map_hint':
          'Drag the map or type 3 letters to find a place in Erode.',
      'pickup_location_label': 'Pickup location',
      'drop_destination_label': 'Drop destination',
      'drop_pin_destination_title': 'Drop pin for destination',
      'drop_pin_pickup_title': 'Drop pin for pickup',
      'finding_street_label': 'Finding the exact street address...',
      'move_map_to_select_label': 'Move the map to select',
      'use_as_destination_label': 'Use as Destination',
      'use_as_pickup_label': 'Use as Pickup',
      'pay_via_soundbox': 'Pay your bill via Paytm box',
      'scan_soundbox_qr':
          'Scan the physical soundbox QR and confirm once the amount is paid.',
      'awaiting_hero_payment': 'Waiting for Hero Confirmation...',
      'scan_and_wait_hero':
          'Please scan the Paytm Soundbox and wait while the Hero confirms your bill.',
      'open_upi_scan_soundbox':
          'Open Paytm through the UPI chooser, scan the Hero Paytm Soundbox, and complete the exact bill amount.',
    },
    'ta': {
      'app_title': 'my allin1',
      'greeting': 'வணக்கம்',
      'what_need_today': 'இன்று என்ன வேண்டும்?',
      'bike_taxi_title': 'பைக் டாக்ஸி',
      'bike_taxi_subtitle': 'ஈரோட்டில் வேகமான பயணம்',
      'food_delivery_title': 'உணவு டெலிவரி',
      'food_delivery_subtitle': '16வது ரோடு சிறப்புகள்',
      'grocery_title': 'மளிகை',
      'grocery_subtitle': 'புதியதும் வேகமும்',
      'tech_store_title': 'டெக் ஸ்டோர்',
      'tech_store_subtitle': 'NJ TECH சாதனங்கள்',
      'custom_order_title': 'கஸ்டம் ஆர்டர்',
      'custom_order_subtitle': 'சிறப்பு சேவையை கேளுங்கள்',
      'broadband_title': 'இணைய சேவை',
      'broadband_subtitle': 'உங்கள் இணைய சேவையை நிர்வகிக்கவும்',
      'mobile_puncture_title': 'மொபைல் பஞ்சர்',
      'mobile_puncture_subtitle': 'விரைவு பஞ்சர் பழுது பார்க்க',
      'pharmacy_title': 'மருந்தகம்',
      'pharmacy_subtitle': 'மருந்துகள் டெலிவரி',
      'book_puncture': 'பஞ்சருக்கு புக் செய்யவா?',
      'call_now': 'இப்போதே அழைக்கவும்',
      'later': 'பிறகு',
      'service_coming_soon': 'விரைவில் வருகிறது!',
      'language_label': 'மொழி',
      'home_label': 'முகப்பு',
      'chat_label': 'நேரலை விலைகள்',
      'rides_label': 'ப்ளே சோன்',
      'account_label': 'கணக்கு',
      'my_rides_label': 'என் பயணங்கள்',
      'live_rates_label': 'நேரலை விலைகள்',
      'play_zone_label': 'ப்ளே சோன்',
      'live_label': 'நேரலை',
      'erode_label': 'ஈரோடு, தமிழ்நாடு',
      'live_rates_title': 'நேரலை விலைகள்',
      'live_rates_subtitle':
          'ஈரோட்டிற்கான தங்கம், வெள்ளி, எரிபொருள் விலைகள் ஒரே பார்வையில்.',
      'today_price_label': 'இன்றைய விலை',
      'play_zone_title': 'ப்ளே சோன்',
      'play_zone_subtitle':
          'NJ TECH 3x3 புதிரை தீர்த்து உங்கள் சிறந்த நேரத்தை வெல்லுங்கள்.',
      'sliding_puzzle_title': 'சறுக்கும் புதிர் விளையாட்டு',
      'moves_label': 'நகர்வுகள்',
      'time_label': 'நேரம்',
      'reset_label': 'மீட்டமை',
      'play_again_label': 'மீண்டும் விளையாடு',
      'puzzle_instruction':
          'NJ TECH மற்றும் ஈரோடு வடிவங்களை சரியாக ஒழுங்குபடுத்து.',
      'solved_title': 'நீங்கள் தீர்த்துவிட்டீர்கள்!',
      'solved_message_intro': 'சிறப்பான நகர்வுகள்!',
      'bike_label': 'பைக்',
      'auto_label': 'ஆட்டோ',
      'cab_label': 'கார்',
      'parcel_label': 'பார்சல்',
      'where_to_go_hint': 'எங்கே செல்ல வேண்டும்?',
      'choose_vehicle_label': 'வாகனத்தை தேர்வு செய்',
      'distance_label': 'தூரம்',
      'eta_label': 'நேரம்',
      'choose_destination_title': 'இறங்கும் இடத்தை தேர்வு செய்',
      'update_pickup_title': 'பிக்கப் இடத்தை மாற்று',
      'drag_map_hint':
          'ஈரோட்டில் இடம் காண மேப்பை இழுக்கவும் அல்லது 3 எழுத்துகள் தட்டச்சு செய்யவும்.',
      'pickup_location_label': 'பிக்கப் இடம்',
      'drop_destination_label': 'இறங்கும் இடம்',
      'drop_pin_destination_title': 'இறங்கும் இடத்திற்கு பின் இடு',
      'drop_pin_pickup_title': 'பிக்கப் இடத்திற்கு பின் இடு',
      'finding_street_label': 'சரியான தெரு முகவரியை கண்டுபிடிக்கிறது...',
      'move_map_to_select_label': 'தேர்வு செய்ய மேப்பை நகர்த்து',
      'use_as_destination_label': 'இறங்கும் இடமாக பயன்படுத்து',
      'use_as_pickup_label': 'பிக்கப் இடமாக பயன்படுத்து',
      'pay_via_soundbox': 'Paytm சவுண்ட்பாக்ஸ் மூலம் பில் செலுத்தவும்',
      'scan_soundbox_qr':
          'சவுண்ட்பாக்ஸ் QR ஐ ஸ்கேன் செய்து, பணம் செலுத்தியதும் உறுதிசெய்யவும்.',
      'awaiting_hero_payment': 'ஹீரோ உறுதிப்படுத்தலுக்காக காத்திருக்கிறது...',
      'scan_and_wait_hero':
          'Paytm சவுண்ட்பாக்ஸை ஸ்கேன் செய்து, ஹீரோ உங்கள் பில்லை உறுதிப்படுத்தும் வரை காத்திருக்கவும்.',
      'open_upi_scan_soundbox':
          'UPI தேர்வு மூலம் Paytm ஐ திறந்து, ஹீரோவின் Paytm சவுண்ட்பாக்ஸை ஸ்கேன் செய்து, சரியான பில் தொகையை செலுத்தவும்.',
    },
    'tg': {
      'app_title': 'my allin1',
      'greeting': 'Vanakkam',
      'what_need_today': 'Innaiku enna venum?',
      'bike_taxi_title': 'Bike Taxi',
      'bike_taxi_subtitle': 'Erode la fast ride',
      'food_delivery_title': 'Food Delivery',
      'food_delivery_subtitle': '16th road special sapadu',
      'grocery_title': 'Grocery',
      'grocery_subtitle': 'Fresh ahum fast ahum',
      'tech_store_title': 'Tech Store',
      'tech_store_subtitle': 'NJ TECH gadgets',
      'custom_order_title': 'Custom Order',
      'custom_order_subtitle': 'Special service kekkalam',
      'broadband_title': 'Internet Bill',
      'broadband_subtitle': 'Internet service manage pannu',
      'mobile_puncture_title': 'Mobile Puncture',
      'mobile_puncture_subtitle': 'Vandi puncture repair on call',
      'pharmacy_title': 'Pharmacy',
      'pharmacy_subtitle': 'Medicine delivery',
      'book_puncture': 'Puncture-ku book pannu?',
      'call_now': 'Call Now',
      'later': 'Apram',
      'service_coming_soon': 'Seekiram varudhu!',
      'language_label': 'Language',
      'home_label': 'Home',
      'chat_label': 'Live Rates',
      'rides_label': 'Play Zone',
      'account_label': 'Account',
      'my_rides_label': 'En rides',
      'live_rates_label': 'Live Rates',
      'play_zone_label': 'Play Zone',
      'live_label': 'Live',
      'erode_label': 'Erode, Tamil Nadu',
      'live_rates_title': 'Live Rates',
      'live_rates_subtitle':
          'Gold, silver, petrol rate ellam ore glance la paakalam.',
      'today_price_label': 'Innaiku rate',
      'play_zone_title': 'Play Zone',
      'play_zone_subtitle':
          'NJ TECH 3x3 puzzle solve panni unga best time beat pannunga.',
      'sliding_puzzle_title': 'Sarukkum Puthir Vilayattu',
      'moves_label': 'Moves',
      'time_label': 'Time',
      'reset_label': 'Reset',
      'play_again_label': 'Play Again',
      'puzzle_instruction':
          'NJ TECH um Erode pattern pieces um straight ah align pannunga.',
      'solved_title': 'Neenga theerthuttinga!',
      'solved_message_intro': 'Semma moves!',
      'bike_label': 'Bike',
      'auto_label': 'Auto',
      'cab_label': 'Cab',
      'parcel_label': 'Parcel',
      'where_to_go_hint': 'Enga poganum?',
      'choose_vehicle_label': 'Vehicle choose pannu',
      'distance_label': 'Distance',
      'eta_label': 'ETA',
      'choose_destination_title': 'Destination choose pannu',
      'update_pickup_title': 'Pickup update pannu',
      'drag_map_hint':
          'Erode la place find panna map drag pannunga illa 3 letters type pannunga.',
      'pickup_location_label': 'Pickup location',
      'drop_destination_label': 'Drop destination',
      'drop_pin_destination_title': 'Destination-ku pin podu',
      'drop_pin_pickup_title': 'Pickup-ku pin podu',
      'finding_street_label': 'Exact street address theduthu irukom...',
      'move_map_to_select_label': 'Select panna map move pannunga',
      'use_as_destination_label': 'Destination ah use pannu',
      'use_as_pickup_label': 'Pickup ah use pannu',
      'pay_via_soundbox': 'Paytm soundbox la bill kattru',
      'scan_soundbox_qr':
          'Soundbox QR scan pannitu, amount pay pannitu confirm pannu.',
      'awaiting_hero_payment': 'Hero confirmation ku waiting...',
      'scan_and_wait_hero':
          'Paytm Soundbox scan pannitu, Hero unga bill confirm panna vara wait pannu.',
      'open_upi_scan_soundbox':
          'UPI la Paytm open pannu, Hero Soundbox scan pannu, exact bill amount pay pannu.',
    },
  };

  String _languageCode;

  String get languageCode => _languageCode;

  String get languageLabel {
    switch (_languageCode) {
      case 'ta':
        return 'தமிழ்';
      case 'tg':
        return 'Tanglish';
      default:
        return 'English';
    }
  }

  String t(String key) {
    return _translations[_languageCode]?[key] ??
        _translations['en']?[key] ??
        key;
  }

  Future<void> setLanguage(String code) async {
    if (!_translations.containsKey(code) || code == _languageCode) {
      return;
    }

    _languageCode = code;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _languageCode);
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_prefsKey);
    if (savedLanguage == null ||
        !_translations.containsKey(savedLanguage) ||
        savedLanguage == _languageCode) {
      return;
    }

    _languageCode = savedLanguage;
    notifyListeners();
  }
}
