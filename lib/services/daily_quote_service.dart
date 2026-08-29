// ================================================================
// DailyQuoteService — Allin1 (Aug 19 2026)
// ================================================================
// One motivational line, shown between the greeting and the city on
// the home header. Rotates THREE times a day (morning / afternoon /
// night) and never repeats a line until the whole pool is exhausted.
//
// WHY NOT AI, AND WHY NOT FIRESTORE
//   Both were considered and both were rejected for the same reason:
//   this line is rendered on the very first frame of the home screen,
//   for every customer, every session. A Firestore read would put a
//   network round-trip in front of the app's first paint and cost a
//   document read per user per open — a daily read bill for a piece of
//   decoration. An AI call would be far worse on both counts, and
//   would also make the line non-deterministic, so two people standing
//   next to each other would see different quotes and it would stop
//   feeling like "today's line".
//
//   So the pool is compiled into the app: zero reads, zero latency,
//   works fully offline, and costs nothing on the Spark plan. The
//   price is that adding quotes needs an app update — acceptable for
//   content that is deliberately timeless.
//
// WHY THE SELECTION IS DETERMINISTIC, NOT RANDOM
//   The index is derived from the calendar date and the time slot, NOT
//   from Random(). Three consequences that all matter:
//     1. Everyone in Erode sees the same line at the same time, so it
//        reads as a broadcast rather than noise.
//     2. It survives an app restart — a random pick would hand the
//        customer a different quote every time they reopened the app,
//        which is exactly the "orey quote irukakudathu" complaint in
//        reverse.
//     3. No storage. Nothing to persist, nothing to migrate.
//
// WHY THE STEP-WALK INSTEAD OF seed % length
//   A plain modulo walks the list in order, so the quotes would appear
//   in the same sequence forever and feel like a list being read out.
//   Instead we step through by a stride that is COPRIME with the pool
//   size, which is guaranteed to visit every entry exactly once before
//   any repeat — a full-cycle shuffle with no state and no memory.
// ================================================================

import 'package:flutter/foundation.dart';

import 'tamil_transliteration.dart';

/// Which of the three daily slots a given time falls into.
enum QuoteSlot { morning, afternoon, night }

/// A single line in both languages we actually serve at this size.
/// Tamil is not a translation-for-completeness here — most of Erode
/// reads it faster, and a motivational line that needs decoding isn't
/// motivating.
class DailyQuote {
  final String en;
  final String ta;
  const DailyQuote(this.en, this.ta);
}

class DailyQuoteService {
  DailyQuoteService._();
  static final DailyQuoteService instance = DailyQuoteService._();

  /// Slot boundaries chosen to match how the day is actually lived by
  /// the people using this app, not clock quarters: morning runs to
  /// noon, afternoon through the working part of the day, night from
  /// 5pm when deliveries and rides peak.
  static QuoteSlot slotFor(DateTime now) {
    if (now.hour < 12) return QuoteSlot.morning;
    if (now.hour < 17) return QuoteSlot.afternoon;
    return QuoteSlot.night;
  }

  /// Days since epoch. Deliberately built from the LOCAL y/m/d rather
  /// than `now.difference(epoch).inDays`, so the quote flips at local
  /// midnight instead of at some UTC offset in the middle of the
  /// evening.
  static int _dayIndex(DateTime now) =>
      DateTime(now.year, now.month, now.day).difference(DateTime(2020)).inDays;

  /// Largest stride below [n] that shares no factor with it. Any such
  /// stride generates the full cycle 0..n-1 before repeating, which is
  /// what guarantees "no quote twice until all of them have been seen".
  static int _coprimeStride(int n) {
    if (n <= 2) return 1;
    for (var k = n ~/ 2; k > 1; k--) {
      if (_gcd(k, n) == 1) return k;
    }
    return 1;
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  static DailyQuote _pick(List<DailyQuote> pool, DateTime now) {
    if (pool.isEmpty) return const DailyQuote('', '');
    // 3 slots per day, so this counter advances once every ~8 hours and
    // never collides between slots of the same day.
    final tick = _dayIndex(now) * 3 + slotFor(now).index;
    final stride = _coprimeStride(pool.length);
    return pool[(tick * stride) % pool.length];
  }

  /// Today's line for a CUSTOMER, in the language they've chosen.
  /// [languageCode] comes from LocalizationService.
  ///
  /// CHANGED (Aug 28 2026 — Nizam: "thanglish vachurukanvangaluku
  /// thanglish layum"). 'tg' used to fall through to English on the
  /// reasoning that a Thanglish reader is comfortable with the Latin
  /// script. True of the script, false of the language: someone who
  /// picked Thanglish picked TAMIL, and handing them an English line
  /// while the rest of their app speaks Tamil is the odd one out. They
  /// now get the Tamil line, transliterated.
  String forCustomer(String languageCode, {DateTime? now}) =>
      _text(_pick(_customerQuotes, now ?? DateTime.now()), languageCode);

  /// Today's line for a HERO. A separate pool on purpose: a hero opens
  /// this app to earn, often early, often tired, and a generic "believe
  /// in yourself" reads as hollow next to a line about the work itself.
  String forHero(String languageCode, {DateTime? now}) =>
      _text(_pick(_heroQuotes, now ?? DateTime.now()), languageCode);

  /// Today's line for a SELLER.
  String forSeller(String languageCode, {DateTime? now}) =>
      _text(_pick(_sellerQuotes, now ?? DateTime.now()), languageCode);

  /// Today's line for the ADMIN.
  String forAdmin(String languageCode, {DateTime? now}) =>
      _text(_pick(_adminQuotes, now ?? DateTime.now()), languageCode);

  /// Today's line for whichever app is running.
  ///
  /// The single entry point callers should use. Routing by variant here
  /// rather than at every call site is what stops a seller being told
  /// to "support a local shop today" — which is what a shared pool
  /// would eventually do, and which reads as the app not knowing who it
  /// is talking to.
  String forRole(String variant, String languageCode, {DateTime? now}) =>
      switch (variant) {
        'hero' => forHero(languageCode, now: now),
        'seller' => forSeller(languageCode, now: now),
        'admin' => forAdmin(languageCode, now: now),
        _ => forCustomer(languageCode, now: now),
      };

  /// [forRole], in the form a TTS engine can pronounce.
  String spokenForRole(String variant, String languageCode, {DateTime? now}) {
    final pool = switch (variant) {
      'hero' => _heroQuotes,
      'seller' => _sellerQuotes,
      'admin' => _adminQuotes,
      _ => _customerQuotes,
    };
    return _spoken(_pick(pool, now ?? DateTime.now()), languageCode);
  }

  /// Pool sizes, for the test that guards against a role quietly
  /// running on a handful of lines.
  @visibleForTesting
  static Map<String, int> get poolSizes => <String, int>{
        'customer': _customerQuotes.length,
        'hero': _heroQuotes.length,
        'seller': _sellerQuotes.length,
        'admin': _adminQuotes.length,
      };

  static String _text(DailyQuote q, String languageCode) => switch (languageCode) {
        'ta' => q.ta,
        // Display only — see tamil_transliteration.dart. Anything that
        // SPEAKS this line must use [spokenText] instead, or the TTS
        // engine sounds Latin letters out as English.
        'tg' => TamilTransliteration.toLatin(q.ta),
        _ => q.en,
      };

  /// The same line, in the form a TTS engine can pronounce.
  ///
  /// Thanglish is a reading script, not a speaking one: "kaalai
  /// vanakkam" handed to a ta-IN voice comes out as nonsense. So a
  /// Thanglish reader SEES Latin and HEARS the Tamil original.
  static String _spoken(DailyQuote q, String languageCode) =>
      (languageCode == 'ta' || languageCode == 'tg') ? q.ta : q.en;

  /// Today's customer line as it should be SPOKEN.
  String spokenForCustomer(String languageCode, {DateTime? now}) =>
      _spoken(_pick(_customerQuotes, now ?? DateTime.now()), languageCode);

  /// Today's hero line as it should be SPOKEN.
  String spokenForHero(String languageCode, {DateTime? now}) =>
      _spoken(_pick(_heroQuotes, now ?? DateTime.now()), languageCode);

  // ── CUSTOMER POOL ──────────────────────────────────────────────
  // 33 lines — a prime-ish pool size, so with the coprime stride a
  // customer sees eleven days of unique lines before anything returns.
  static const List<DailyQuote> _customerQuotes = <DailyQuote>[
    DailyQuote('Small steps every day build a big life.',
        'தினமும் ஒரு சிறு அடி, வாழ்க்கையை பெரிதாக்கும்.'),
    DailyQuote('Today is a good day to start something.',
        'ஏதாவது ஒன்றைத் தொடங்க இன்று நல்ல நாள்.'),
    DailyQuote('Your effort today is tomorrow’s comfort.',
        'இன்றைய உழைப்பே நாளைய நிம்மதி.'),
    DailyQuote('Be kind. It costs nothing and changes everything.',
        'அன்பாக இரு. செலவே இல்லை, ஆனால் எல்லாம் மாறும்.'),
    DailyQuote('Slow progress is still progress.',
        'மெதுவான முன்னேற்றமும் முன்னேற்றம் தான்.'),
    DailyQuote('Do the thing you keep postponing.',
        'தள்ளிப் போட்டுக்கொண்டிருப்பதை இன்று செய்.'),
    DailyQuote('A calm mind solves faster than a busy one.',
        'அமைதியான மனம் வேகமாக தீர்வு காணும்.'),
    DailyQuote('Support a local shop today.',
        'இன்று ஒரு உள்ளூர் கடையை ஆதரி.'),
    DailyQuote('You are closer than you were yesterday.',
        'நேற்றை விட இன்று நீ நெருங்கிவிட்டாய்.'),
    DailyQuote('Good things take the time they take.',
        'நல்லது நடக்க அதற்குரிய நேரம் தேவை.'),
    DailyQuote('Ask for help. That is strength, not weakness.',
        'உதவி கேள். அது பலவீனம் அல்ல, பலம்.'),
    DailyQuote('Finish one thing before starting three.',
        'மூன்றைத் தொடங்கும் முன் ஒன்றை முடி.'),
    DailyQuote('Your health is the wealth you actually spend.',
        'உடல்நலமே நீ உண்மையில் செலவிடும் செல்வம்.'),
    DailyQuote('Say thank you to someone today.',
        'இன்று யாரிடமாவது நன்றி சொல்.'),
    DailyQuote('Plans fail. Planning does not.',
        'திட்டங்கள் தோற்கலாம், திட்டமிடுவது தோற்காது.'),
    DailyQuote('Rest is part of the work, not a break from it.',
        'ஓய்வும் வேலையின் ஒரு பகுதியே, தடை அல்ல.'),
    DailyQuote('Spend on what lasts, not on what shines.',
        'மின்னுவதற்கு அல்ல, நிலைப்பதற்குச் செலவு செய்.'),
    DailyQuote('One honest conversation fixes ten assumptions.',
        'ஒரு நேர்மையான உரையாடல் பத்து ஊகங்களைத் தீர்க்கும்.'),
    DailyQuote('You do not need a new year to begin.',
        'தொடங்க புத்தாண்டு தேவையில்லை.'),
    DailyQuote('Keep your word, especially the small ones.',
        'சொன்ன சொல்லைக் காப்பாற்று, சிறியதாக இருந்தாலும்.'),
    DailyQuote('Learn one new thing before you sleep.',
        'தூங்கும் முன் ஒன்றைக் கற்றுக்கொள்.'),
    DailyQuote('Comparison steals the joy you already have.',
        'ஒப்பீடு உன்னிடம் உள்ள மகிழ்ச்சியைத் திருடும்.'),
    DailyQuote('Call the person you have been meaning to call.',
        'அழைக்க நினைத்திருந்தவரை இன்று அழை.'),
    DailyQuote('Discipline is choosing later over now.',
        'ஒழுக்கம் என்பது இப்போதைக்கு பதில் பின்னரைத் தேர்வது.'),
    DailyQuote('A clean start beats a perfect plan.',
        'சரியான திட்டத்தை விட தெளிவான தொடக்கம் மேல்.'),
    DailyQuote('Money returns. Time does not.',
        'பணம் திரும்பி வரும், நேரம் வராது.'),
    DailyQuote('Be the reason someone smiles today.',
        'இன்று ஒருவர் சிரிப்பதற்கு நீ காரணமாக இரு.'),
    DailyQuote('Fix the small leak before it floods.',
        'வெள்ளமாகும் முன் சிறு கசிவை அடை.'),
    DailyQuote('Consistency beats intensity.',
        'தீவிரத்தை விட தொடர்ச்சி வெல்லும்.'),
    DailyQuote('Every expert was once a beginner.',
        'ஒவ்வொரு நிபுணரும் ஒரு காலத்தில் தொடக்கநிலையே.'),
    DailyQuote('Do it badly rather than not at all.',
        'செய்யாமல் இருப்பதை விட மோசமாகச் செய்வது மேல்.'),
    DailyQuote('Trust builds slowly and breaks fast.',
        'நம்பிக்கை மெதுவாக வளரும், வேகமாக உடையும்.'),
    DailyQuote('Erode grows when we choose each other.',
        'நாம் ஒருவரையொருவர் தேர்ந்தெடுக்கும்போது ஈரோடு வளரும்.'),

    // ── added Aug 28 2026 (Nizam: 300 more, role-aware) ──
    DailyQuote(
        'A good day starts with one clear decision.',
        'ஒரு தெளிவான முடிவுதான் நல்ல நாளின் ஆரம்பம்.'),
    DailyQuote(
        'Buy what you need, not what you were shown.',
        'காட்டியதை அல்ல, தேவையானதை வாங்குங்க.'),
    DailyQuote(
        'The best deal is the one you actually use.',
        'நீங்க உபயோகிக்கிற பொருள்தான் சிறந்த டீல்.'),
    DailyQuote(
        'Patience at the counter saves money at home.',
        'கடையில் பொறுமை, வீட்டில் சேமிப்பு.'),
    DailyQuote(
        'Ask the price before you fall in love with it.',
        'பிடிக்கும் முன்னே விலையை கேளுங்க.'),
    DailyQuote(
        'A local shop remembers your name. Keep it alive.',
        'உங்க பேரை நினைவு வைக்கிற கடையை காப்பாத்துங்க.'),
    DailyQuote(
        'Your time is worth more than the queue.',
        'வரிசையை விட உங்க நேரம் மதிப்பானது.'),
    DailyQuote(
        'Order less, enjoy more.',
        'குறைவா ஆர்டர் பண்ணுங்க, அதிகமா ருசிங்க.'),
    DailyQuote(
        'Pay a fair price and sleep well.',
        'நியாயமான விலை கொடுங்க, நிம்மதியா தூங்குங்க.'),
    DailyQuote(
        'The cheapest thing twice costs more than the good thing once.',
        'மலிவானது இரண்டு முறை, நல்லது ஒரு முறை — எது மிச்சம்?'),
    DailyQuote(
        'Read the review, then trust your gut.',
        'விமர்சனம் படிங்க, பிறகு மனசை கேளுங்க.'),
    DailyQuote(
        'Small orders build big habits.',
        'சின்ன ஆர்டர்கள்தான் பெரிய பழக்கம்.'),
    DailyQuote(
        'A kind word to the delivery boy costs nothing.',
        'டெலிவரி பையனுக்கு ஒரு நல்ல வார்த்தை — செலவே இல்லை.'),
    DailyQuote(
        'Plan the week, and the week stops planning you.',
        'வாரத்தை திட்டமிடுங்க, இல்லைனா வாரம் உங்களை திட்டமிடும்.'),
    DailyQuote(
        'Waiting is easier when someone is working for you.',
        'உங்களுக்காக ஒருத்தர் உழைக்கும்போது காத்திருப்பது சுலபம்.'),
    DailyQuote(
        'Try the shop nobody talks about.',
        'யாரும் பேசாத கடையை ஒரு முறை முயற்சி பண்ணுங்க.'),
    DailyQuote(
        'Good food is worth the extra ten minutes.',
        'நல்ல சாப்பாட்டுக்கு பத்து நிமிஷம் காத்திருக்கலாம்.'),
    DailyQuote(
        'Spend on health before you spend on cure.',
        'மருந்துக்கு முன்னாடி உடம்புக்கு செலவு பண்ணுங்க.'),
    DailyQuote(
        'The list you make is the money you save.',
        'நீங்க எழுதுற லிஸ்ட்தான் நீங்க சேமிக்கிற பணம்.'),
    DailyQuote(
        'Say what you want clearly. Everyone wins.',
        'தெளிவா சொல்லுங்க — எல்லாருக்கும் நல்லது.'),
    DailyQuote(
        'A refund is a right, not a favour.',
        'திரும்ப பணம் வாங்குறது உரிமை, உபகாரம் இல்லை.'),
    DailyQuote(
        'Reward the shop that treated you well.',
        'நல்லா நடத்தின கடைக்கு திரும்ப போங்க.'),
    DailyQuote(
        'Today\'s small saving is next month\'s freedom.',
        'இன்னைக்கு சின்ன சேமிப்பு, அடுத்த மாசம் சுதந்திரம்.'),
    DailyQuote(
        'Trust the shop that tells you the truth.',
        'உண்மை சொல்ற கடையை நம்புங்க.'),
    DailyQuote(
        'You do not need everything today.',
        'எல்லாமே இன்னைக்கே வேணும்னு இல்லை.'),
    DailyQuote(
        'Compare two, not twenty.',
        'இரண்டை ஒப்பிடுங்க, இருபது இல்லை.'),
    DailyQuote(
        'A clean kitchen makes cheaper food taste better.',
        'சுத்தமான சமையலறை மலிவான சாப்பாட்டையும் ருசியாக்கும்.'),
    DailyQuote(
        'Tip when you can. It reaches a real family.',
        'முடிஞ்சப்போ டிப் கொடுங்க — அது ஒரு குடும்பத்தை சேரும்.'),
    DailyQuote(
        'The best time to fix something is before it breaks.',
        'உடையுறதுக்கு முன்னாடி சரி பண்ணுறதுதான் சரியான நேரம்.'),
    DailyQuote(
        'Ask for help early, not after it is too late.',
        'தாமதமாகுறதுக்கு முன்னாடி உதவி கேளுங்க.'),
    DailyQuote(
        'Your feedback changes what tomorrow looks like.',
        'உங்க கருத்துதான் நாளைய மாற்றம்.'),
    DailyQuote(
        'Choose the shop, not the discount.',
        'தள்ளுபடியை அல்ல, கடையை தேர்ந்தெடுங்க.'),
    DailyQuote(
        'Home cooked once a week is a gift to yourself.',
        'வாரம் ஒரு முறை வீட்டு சமையல் — உங்களுக்கே ஒரு பரிசு.'),
    DailyQuote(
        'Being early is a kind of respect.',
        'முன்னாடியே வர்றது ஒரு மரியாதை.'),
    DailyQuote(
        'Erode grows every time you choose Erode.',
        'நீங்க ஈரோட்டை தேர்ந்தெடுக்கும்போதெல்லாம் ஈரோடு வளரும்.'),
    DailyQuote(
        'A promise kept is worth more than a discount given.',
        'கொடுத்த வாக்கு, கொடுத்த தள்ளுபடியை விட பெரிசு.'),
    DailyQuote(
        'Slow down at the door. Say hello.',
        'வாசல்ல ஒரு நிமிஷம் நில்லுங்க — ஒரு வணக்கம் சொல்லுங்க.'),
    DailyQuote(
        'What you repeat becomes who you are.',
        'நீங்க திரும்பத் திரும்ப செய்றதுதான் நீங்க.'),
    DailyQuote(
        'A budget is freedom wearing a boring name.',
        'பட்ஜெட் என்பது சுதந்திரத்தின் சாதாரண பெயர்.'),
    DailyQuote(
        'Order for your family before you order for your mood.',
        'மனசுக்காக ஆர்டர் பண்ணுறதுக்கு முன்னாடி குடும்பத்துக்காக பண்ணுங்க.'),
    DailyQuote(
        'The quiet shopkeeper often has the best price.',
        'அமைதியான கடைக்காரர்கிட்டதான் நல்ல விலை இருக்கும்.'),
    DailyQuote(
        'Do not pay twice for the same mistake.',
        'ஒரே தப்புக்கு இரண்டு முறை காசு கொடுக்காதீங்க.'),
    DailyQuote(
        'Every rupee has a job. Give it one.',
        'ஒவ்வொரு ரூபாய்க்கும் ஒரு வேலை கொடுங்க.'),
    DailyQuote(
        'Buy once. Buy right.',
        'ஒரு முறை வாங்குங்க — சரியா வாங்குங்க.'),
    DailyQuote(
        'The best offer is honesty about what you need.',
        'தேவை என்னனு நேர்மையா தெரிஞ்சுக்கிறதுதான் சிறந்த ஆஃபர்.'),
    DailyQuote(
        'Cook one new dish this week.',
        'இந்த வாரம் ஒரு புது சமையல் முயற்சி பண்ணுங்க.'),
    DailyQuote(
        'A phone lasts longer than the trend that sold it.',
        'விளம்பரத்தை விட ஃபோன் அதிக நாள் இருக்கும்.'),
    DailyQuote(
        'Take the stairs today.',
        'இன்னைக்கு படிக்கட்டுல ஏறுங்க.'),
    DailyQuote(
        'Give the small shop your first chance, not your last.',
        'சின்ன கடைக்கு கடைசி வாய்ப்பு இல்ல — முதல் வாய்ப்பு கொடுங்க.'),
    DailyQuote(
        'Spend a little on your parents today.',
        'இன்னைக்கு அப்பா அம்மாவுக்கு கொஞ்சம் செலவு பண்ணுங்க.'),
    DailyQuote(
        'A repaired thing has a story. A new thing has a bill.',
        'சரி பண்ணினதுக்கு கதை உண்டு — புதுசுக்கு பில் மட்டும்தான்.'),
    DailyQuote(
        'Do not buy to impress people you do not like.',
        'பிடிக்காதவங்களை கவர வாங்காதீங்க.'),
    DailyQuote(
        'Water first, coffee second.',
        'முதல்ல தண்ணி, அப்புறம் காபி.'),
    DailyQuote(
        'Your best purchase this year might be a good night\'s sleep.',
        'இந்த வருஷத்து சிறந்த வாங்கல் — நல்ல தூக்கமா கூட இருக்கலாம்.'),
    DailyQuote(
        'Call before you complain. It usually works.',
        'புகார் சொல்றதுக்கு முன்னாடி ஒரு கால் பண்ணுங்க — பெரும்பாலும் வேலை செய்யும்.'),
    DailyQuote(
        'Keep the receipt. Keep the peace.',
        'பில்லை வையுங்க — நிம்மதியை வையுங்க.'),
    DailyQuote(
        'An empty cart at night saves a full regret in the morning.',
        'ராத்திரி காலி கார்ட், காலைல வருத்தத்தை தவிர்க்கும்.'),
    DailyQuote(
        'Learn the price of one thing you buy often.',
        'அடிக்கடி வாங்குற ஒரு பொருளோட விலையை தெரிஞ்சுக்குங்க.'),
    DailyQuote(
        'Share the offer with someone who needs it more.',
        'அதிகம் தேவைப்படுறவங்ககிட்ட ஆஃபரை பகிருங்க.'),
    DailyQuote(
        'Being on time is cheaper than being sorry.',
        'நேரத்துக்கு வர்றது, மன்னிப்பு கேட்குறதை விட மலிவு.'),
    DailyQuote(
        'A full fridge is not the same as a good meal.',
        'நிறைஞ்ச ஃபிரிட்ஜ், நல்ல சாப்பாடு இல்லை.'),
    DailyQuote(
        'Pick the item, not the packaging.',
        'பேக்கிங்கை அல்ல, பொருளை தேர்ந்தெடுங்க.'),
    DailyQuote(
        'Walk to the nearby shop once a week.',
        'வாரம் ஒரு முறை பக்கத்து கடைக்கு நடந்து போங்க.'),
    DailyQuote(
        'Say the problem simply and it gets solved simply.',
        'பிரச்சனையை எளிமையா சொன்னா, தீர்வும் எளிமையா வரும்.'),
    DailyQuote(
        'The thing you use daily deserves the better price.',
        'தினமும் உபயோகிக்கிறதுக்குதான் நல்ல விலை கொடுக்கணும்.'),
    DailyQuote(
        'Save the number of the shop that helped you.',
        'உதவின கடையோட நம்பரை சேவ் பண்ணுங்க.'),
    DailyQuote(
        'Two good shirts beat six cheap ones.',
        'ஆறு மலிவான சட்டையை விட ரெண்டு நல்ல சட்டை மேல்.'),
    DailyQuote(
        'Order early. Everyone is calmer.',
        'முன்னாடியே ஆர்டர் பண்ணுங்க — எல்லாரும் நிம்மதியா இருப்பாங்க.'),
    DailyQuote(
        'A little planning removes a lot of arguing.',
        'கொஞ்சம் திட்டமிடல், நிறைய வாதத்தை தவிர்க்கும்.'),
    DailyQuote(
        'Do not let a sale decide your budget.',
        'தள்ளுபடி உங்க பட்ஜெட்டை முடிவு பண்ண விடாதீங்க.'),
    DailyQuote(
        'The neighbour\'s advice is free and often right.',
        'பக்கத்து வீட்டு அறிவுரை இலவசம் — பெரும்பாலும் சரியும் கூட.'),
    DailyQuote(
        'Finish the leftovers before the new order.',
        'புது ஆர்டருக்கு முன்னாடி மிச்சத்தை முடிங்க.'),
    DailyQuote(
        'Choose the payment that leaves no fee behind.',
        'கட்டணம் இல்லாத பணப் பரிமாற்றத்தை தேர்ந்தெடுங்க.'),
    DailyQuote(
        'You are allowed to ask for a better price.',
        'நல்ல விலை கேட்குறது உங்க உரிமை.'),
    DailyQuote(
        'The simplest option is usually the right one.',
        'எளிமையான தேர்வுதான் பெரும்பாலும் சரியானது.'),
  ];

  // ── HERO POOL ──────────────────────────────────────────────────
  // Written for someone about to go out and work: earnings, safety,
  // customer trust, and stamina. Nothing abstract.
  static const List<DailyQuote> _heroQuotes = <DailyQuote>[
    DailyQuote('Every ride today is money in your pocket.',
        'இன்றைய ஒவ்வொரு ரைடும் உன் பையில் பணம்.'),
    DailyQuote('100% of what you earn stays yours.',
        'நீ சம்பாதிப்பதில் 100% உனக்கே.'),
    DailyQuote('A polite hello earns the next booking.',
        'ஒரு அன்பான வணக்கம் அடுத்த புக்கிங்கைத் தரும்.'),
    DailyQuote('Helmet on. Your family is waiting.',
        'ஹெல்மெட் போடு. உன் குடும்பம் காத்திருக்கிறது.'),
    DailyQuote('Start early. The first hour is the easiest money.',
        'சீக்கிரம் தொடங்கு. முதல் மணி நேரமே எளிதான வருமானம்.'),
    DailyQuote('One good rating today brings ten rides tomorrow.',
        'இன்று ஒரு நல்ல மதிப்பீடு, நாளை பத்து ரைடு.'),
    DailyQuote('Drink water. Tired hands make mistakes.',
        'தண்ணீர் குடி. களைத்த கைகள் தவறு செய்யும்.'),
    DailyQuote('You are not driving. You are building an income.',
        'நீ ஓட்டவில்லை, ஒரு வருமானத்தைக் கட்டுகிறாய்.'),
    DailyQuote('The customer remembers how you made them feel.',
        'நீ எப்படி நடத்தினாய் என்பதையே வாடிக்கையாளர் நினைவில் வைப்பார்.'),
    DailyQuote('Slow down at the turn. The order can wait.',
        'திருப்பத்தில் மெதுவாகு. ஆர்டர் காத்திருக்கும்.'),
    DailyQuote('Ten small trips beat one perfect trip you waited for.',
        'காத்திருந்த ஒரு பெரிய டிரிப்பை விட பத்து சிறிய டிரிப் மேல்.'),
    DailyQuote('Your name in Erode is worth more than one fare.',
        'ஈரோட்டில் உன் பெயர் ஒரு கட்டணத்தை விட மதிப்புமிக்கது.'),
    DailyQuote('Clean vehicle, better tips.',
        'சுத்தமான வாகனம், அதிக டிப்ஸ்.'),
    DailyQuote('Turn on. Show up. That is 90% of it.',
        'ஆன் செய். வந்து நில். அதுவே 90%.'),
    DailyQuote('Rest properly tonight so tomorrow pays more.',
        'இன்று நன்றாக ஓய்வெடு, நாளை அதிகம் கிடைக்கும்.'),
    DailyQuote('Nobody built savings in one day. Keep going.',
        'ஒரே நாளில் யாரும் சேமிப்பு உருவாக்கவில்லை. தொடர்ந்து செய்.'),
    DailyQuote('Know the address before you start the trip.',
        'கிளம்பும் முன் முகவரியை தெளிவாக அறிந்துகொள்.'),
    DailyQuote('An honest fare brings the customer back.',
        'நேர்மையான கட்டணம் வாடிக்கையாளரை மீண்டும் அழைத்து வரும்.'),
    DailyQuote('Peak hours pay double. Be out there.',
        'கூட்ட நேரத்தில் இரட்டிப்பு வருமானம். வெளியே இரு.'),
    DailyQuote('You are your own boss today. Act like one.',
        'இன்று நீயே முதலாளி. அப்படியே நடந்துகொள்.'),
    DailyQuote('Answer the call fast. Speed wins the ride.',
        'விரைவாக பதிலளி. வேகமே ரைடை வெல்லும்.'),
    DailyQuote('Fuel your bike and your body.',
        'வண்டிக்கும் உடலுக்கும் எரிபொருள் நிரப்பு.'),
    DailyQuote('Bad weather days pay the best. Stay safe though.',
        'மோசமான வானிலையில் வருமானம் அதிகம். ஆனால் பத்திரமாக இரு.'),

    // ── added Aug 28 2026 ──
    DailyQuote(
        'Boss, I am your dude. Do not worry — the money will come.',
        'பாஸ், நான் உங்க தோஸ்த். கவலைப்படாதீங்க — காசு வரும்.'),
    DailyQuote(
        'Every trip you finish is money nobody can take back.',
        'நீங்க முடிக்கிற ஒவ்வொரு டிரிப்பும் யாரும் பறிக்க முடியாத காசு.'),
    DailyQuote(
        'A smile at pickup is worth more than a shortcut.',
        'பிக்கப்ல ஒரு புன்னகை, குறுக்கு வழியை விட மதிப்பானது.'),
    DailyQuote(
        'Slow day today? The road pays back next week.',
        'இன்னைக்கு வேலை குறைவா? அடுத்த வாரம் ரோடு திருப்பி தரும்.'),
    DailyQuote(
        'Ride safe. Your family is the real destination.',
        'பத்திரமா ஓட்டுங்க — உங்க குடும்பம்தான் நிஜமான இலக்கு.'),
    DailyQuote(
        'The customer remembers how you treated them, not the traffic.',
        'ட்ராஃபிக்கை இல்லை, நீங்க நடந்துகிட்ட விதத்தைதான் அவங்க நினைவு வைப்பாங்க.'),
    DailyQuote(
        'Boss, you are not alone on this road. I am right here.',
        'பாஸ், இந்த ரோட்ல நீங்க தனியா இல்ல — நான் இருக்கேன்.'),
    DailyQuote(
        'Ten good trips beat one big one.',
        'ஒரு பெரிய டிரிப்பை விட பத்து நல்ல டிரிப் மேல்.'),
    DailyQuote(
        'Drink water. A tired rider earns less than a rested one.',
        'தண்ணி குடிங்க — களைச்ச டிரைவர் குறைவாத்தான் சம்பாதிப்பார்.'),
    DailyQuote(
        'Say hello first. It changes the whole ride.',
        'முதல்ல வணக்கம் சொல்லுங்க — பயணமே மாறிடும்.'),
    DailyQuote(
        'Your rating is your salary. Protect it gently.',
        'உங்க ரேட்டிங்தான் உங்க சம்பளம் — அதை பத்திரமா பாத்துக்கோங்க.'),
    DailyQuote(
        'Boss, today\'s earning is small. Today\'s habit is not.',
        'பாஸ், இன்னைக்கு வருமானம் சின்னது — பழக்கம் சின்னது இல்லை.'),
    DailyQuote(
        'Helping with a heavy bag costs one minute and earns a lifetime.',
        'கனமான பையை தூக்கி கொடுக்க ஒரு நிமிஷம் — கிடைக்குறது வாழ்நாள் மரியாதை.'),
    DailyQuote(
        'Rain days are the days customers remember you.',
        'மழை நாள்லதான் வாடிக்கையாளர் உங்களை நினைவு வைப்பாங்க.'),
    DailyQuote(
        'Do not race the clock. Beat it by starting early.',
        'கடிகாரத்தோட ஓடாதீங்க — முன்னாடியே கிளம்புங்க.'),
    DailyQuote(
        'A clean vehicle earns a bigger tip than a fast one.',
        'வேகமான வண்டியை விட சுத்தமான வண்டிக்கு டிப் அதிகம்.'),
    DailyQuote(
        'You are running a business, boss. Not just a bike.',
        'பாஸ், நீங்க வண்டி ஓட்டல — ஒரு தொழில் நடத்துறீங்க.'),
    DailyQuote(
        'Cancel less. Every completed ride builds your name.',
        'கேன்சல் குறைங்க — முடிச்ச ஒவ்வொரு ரைடும் உங்க பேரை கட்டும்.'),
    DailyQuote(
        'Tell the customer you are coming. Silence feels like delay.',
        'வர்றேன்னு சொல்லுங்க — மௌனம் தாமதமா தெரியும்.'),
    DailyQuote(
        'Boss, rest is not lost income. It is next week\'s income.',
        'பாஸ், ஓய்வு நஷ்டம் இல்ல — அடுத்த வாரத்து வருமானம்.'),
    DailyQuote(
        'The road is long. Take it one pickup at a time.',
        'ரோடு நீளம்தான் — ஒரு பிக்கப் ஒரு பிக்கப்பா எடுங்க.'),
    DailyQuote(
        'Nobody was born knowing every street. You learned them.',
        'எல்லா தெருவும் தெரிஞ்சு யாரும் பொறக்கல — நீங்க கத்துக்கிட்டீங்க.'),
    DailyQuote(
        'Your honesty today is your regular customer tomorrow.',
        'இன்னைக்கு நேர்மை, நாளைக்கு நிரந்தர வாடிக்கையாளர்.'),
    DailyQuote(
        'Wear the helmet. I want you here tomorrow, boss.',
        'ஹெல்மெட் போடுங்க — நாளைக்கும் நீங்க இருக்கணும் பாஸ்.'),
    DailyQuote(
        'Eat properly. You cannot pour from an empty tank.',
        'சரியா சாப்பிடுங்க — காலி டேங்க்ல இருந்து ஊத்த முடியாது.'),
    DailyQuote(
        'A hard morning does not decide the evening.',
        'கஷ்டமான காலை, மாலையை தீர்மானிக்காது.'),
    DailyQuote(
        'Boss, your work feeds a family. That is not a small job.',
        'பாஸ், உங்க வேலை ஒரு குடும்பத்தை காப்பாத்துது — அது சின்ன வேலை இல்ல.'),
    DailyQuote(
        'Wait two extra minutes. It saves a one star.',
        'இரண்டு நிமிஷம் அதிகமா காத்திருங்க — ஒரு நட்சத்திரம் மிச்சம்.'),
    DailyQuote(
        'Fuel is a cost. Rudeness is a bigger one.',
        'பெட்ரோல் ஒரு செலவு — முரட்டுத்தனம் அதை விட பெரிய செலவு.'),
    DailyQuote(
        'Check the tyres before the road checks them for you.',
        'ரோடு சோதிக்கிறதுக்கு முன்னாடி டயரை நீங்க சோதிங்க.'),
    DailyQuote(
        'Boss, the app counts every trip. Nothing you do is wasted.',
        'பாஸ், ஆப் ஒவ்வொரு டிரிப்பையும் கணக்கு வைக்குது — எதுவும் வீண் போகாது.'),
    DailyQuote(
        'Peak hours reward the rider who is already out.',
        'வெளியே இருக்கிற டிரைவருக்குதான் பீக் அவர் பலன்.'),
    DailyQuote(
        'Talk less, arrive sooner. That is the whole trick.',
        'குறைவா பேசி சீக்கிரம் போய் சேருங்க — அவ்ளோதான் ரகசியம்.'),
    DailyQuote(
        'Your worst customer today is one ride out of many.',
        'இன்னைக்கு மோசமான வாடிக்கையாளர், பல ரைட்ல ஒண்ணுதான்.'),
    DailyQuote(
        'Save a little from every good day. Bad days come.',
        'நல்ல நாள்ல கொஞ்சம் சேமிங்க — மோசமான நாளும் வரும்.'),
    DailyQuote(
        'Boss, you showed up today. That is already most of it.',
        'பாஸ், இன்னைக்கு நீங்க வந்தீங்க — அதுவே பெரும்பாலும் போதும்.'),
    DailyQuote(
        'Know one shortcut nobody else uses.',
        'யாருக்கும் தெரியாத ஒரு குறுக்கு வழி தெரிஞ்சு வையுங்க.'),
    DailyQuote(
        'Politeness is free and it pays every single day.',
        'பணிவு இலவசம் — ஆனா தினமும் வருமானம் தரும்.'),
    DailyQuote(
        'A good night\'s sleep is a business decision.',
        'நல்ல தூக்கம் ஒரு தொழில் முடிவு.'),
    DailyQuote(
        'Boss, do not compare your day to someone else\'s screen.',
        'பாஸ், இன்னொருத்தர் ஸ்கிரீனோட உங்க நாளை ஒப்பிடாதீங்க.'),
    DailyQuote(
        'Finish what you accepted. That is what makes you a pro.',
        'ஏத்துக்கிட்டதை முடிங்க — அதுதான் தொழில்முறை.'),
    DailyQuote(
        'Every street you learn is money you keep earning.',
        'நீங்க கத்துக்கிற ஒவ்வொரு தெருவும் தொடர்ந்து சம்பாதிக்கும்.'),
    DailyQuote(
        'You are somebody\'s help today. That matters.',
        'இன்னைக்கு நீங்க ஒருத்தருக்கு உதவி — அது முக்கியம்.'),
    DailyQuote(
        'Boss, you are the reason the app works at all.',
        'பாஸ், இந்த ஆப் ஓடுறதே உங்களால தான்.'),
    DailyQuote(
        'Take the long route if it is the safe route.',
        'பாதுகாப்பான வழினா, நீளமான வழியே எடுங்க.'),
    DailyQuote(
        'Park properly. It takes ten seconds and saves an argument.',
        'சரியா நிறுத்துங்க — பத்து விநாடி, ஒரு சண்டை மிச்சம்.'),
    DailyQuote(
        'Boss, one bad rating does not erase a hundred good rides.',
        'பாஸ், ஒரு மோசமான ரேட்டிங், நூறு நல்ல ரைடை அழிக்காது.'),
    DailyQuote(
        'Charge your phone before you charge the road.',
        'ரோட்ல ஏறுறதுக்கு முன்னாடி ஃபோனை சார்ஜ் பண்ணுங்க.'),
    DailyQuote(
        'Carry water. Erode sun does not negotiate.',
        'தண்ணி எடுத்துட்டு போங்க — ஈரோடு வெயில் பேரம் பேசாது.'),
    DailyQuote(
        'Boss, your name travels faster than your bike.',
        'பாஸ், உங்க வண்டியை விட உங்க பேரு வேகமா பயணிக்கும்.'),
    DailyQuote(
        'Confirm the address twice. Save twenty minutes.',
        'முகவரியை இரண்டு முறை உறுதி பண்ணுங்க — இருபது நிமிஷம் மிச்சம்.'),
    DailyQuote(
        'Do not skip breakfast for one more trip.',
        'இன்னொரு டிரிப்புக்காக காலை சாப்பாட்டை விடாதீங்க.'),
    DailyQuote(
        'A calm rider gets a calm customer.',
        'அமைதியான டிரைவர், அமைதியான வாடிக்கையாளர்.'),
    DailyQuote(
        'Boss, save for the day the bike needs service.',
        'பாஸ், வண்டி சர்வீஸ் நாளுக்காக சேமிங்க.'),
    DailyQuote(
        'Know your best area and own it.',
        'உங்க சிறந்த ஏரியாவை தெரிஞ்சு அதுல ராஜாவா இருங்க.'),
    DailyQuote(
        'Photograph the parcel at pickup. It protects you.',
        'பிக்கப்ல பார்சலை படம் எடுங்க — அது உங்களை காக்கும்.'),
    DailyQuote(
        'Boss, the customer waiting is nervous, not angry.',
        'பாஸ், காத்திருக்கிற வாடிக்கையாளர் கோபமா இல்ல — பதட்டமா இருக்காங்க.'),
    DailyQuote(
        'Every helmet strap is a promise to someone at home.',
        'ஒவ்வொரு ஹெல்மெட் பட்டையும் வீட்ல ஒருத்தருக்கு கொடுத்த வாக்கு.'),
    DailyQuote(
        'Do the difficult delivery. Nobody forgets it.',
        'கஷ்டமான டெலிவரியை செய்யுங்க — யாரும் மறக்க மாட்டாங்க.'),
    DailyQuote(
        'Boss, a rainy evening is a hero\'s best hour.',
        'பாஸ், மழை மாலைதான் ஹீரோவோட சிறந்த நேரம்.'),
    DailyQuote(
        'Learn one customer\'s name today.',
        'இன்னைக்கு ஒரு வாடிக்கையாளரோட பேரை கத்துக்குங்க.'),
    DailyQuote(
        'Do not ride angry. Stop, breathe, then go.',
        'கோபத்துல ஓட்டாதீங்க — நில்லுங்க, மூச்சு விடுங்க, அப்புறம் போங்க.'),
    DailyQuote(
        'Boss, you decide your hours. That is real freedom.',
        'பாஸ், நேரத்தை நீங்கதான் முடிவு பண்றீங்க — அதுதான் நிஜ சுதந்திரம்.'),
    DailyQuote(
        'Service the bike before it services you a bill.',
        'பெரிய பில் வர்றதுக்கு முன்னாடி வண்டியை சர்வீஸ் பண்ணுங்க.'),
    DailyQuote(
        'A polite call fixes what a fast ride cannot.',
        'வேகமான ரைடு சரி பண்ணாததை, ஒரு பணிவான கால் சரி பண்ணும்.'),
    DailyQuote(
        'Boss, count the week, not the hour.',
        'பாஸ், மணி நேரத்தை அல்ல, வாரத்தை கணக்கு பாருங்க.'),
    DailyQuote(
        'Help a new rider. You were new once.',
        'புது டிரைவருக்கு உதவுங்க — நீங்களும் ஒரு காலத்துல புதுசுதான்.'),
    DailyQuote(
        'Wear something bright at night.',
        'ராத்திரில பிரகாசமான உடை போடுங்க.'),
    DailyQuote(
        'The order is small. The respect is not.',
        'ஆர்டர் சின்னது — மரியாதை சின்னது இல்லை.'),
    DailyQuote(
        'Boss, do not ride when you cannot see straight.',
        'பாஸ், கண்ணு சரியா தெரியலைனா ஓட்டாதீங்க.'),
    DailyQuote(
        'Keep change ready. It ends the trip smoothly.',
        'சில்லறை ரெடியா வையுங்க — பயணம் நல்லா முடியும்.'),
    DailyQuote(
        'Your uniform is not cloth. It is a promise.',
        'உங்க சீருடை துணி இல்ல — ஒரு வாக்குறுதி.'),
    DailyQuote(
        'Boss, tomorrow\'s first trip starts with tonight\'s sleep.',
        'பாஸ், நாளைய முதல் டிரிப் இன்னைக்கு ராத்திரி தூக்கத்துல ஆரம்பம்.'),
    DailyQuote(
        'A short break is faster than a long mistake.',
        'நீளமான தப்பை விட, சின்ன ஓய்வு வேகமானது.'),
    DailyQuote(
        'Boss, you are building something. Do not stop now.',
        'பாஸ், நீங்க எதையோ கட்டிட்டு இருக்கீங்க — இப்போ நிறுத்தாதீங்க.'),
  ];

  // ── SELLER POOL ────────────────────────────────────────────────
  // NEW (Aug 28 2026 — Nizam: "seller kum daily motivational quote
  // varanum... avangavanga role ku nalla motivator ah irukanum").
  //
  // A separate pool, not a shared one, for the same reason the hero
  // pool exists: "believe in yourself" means nothing to someone
  // deciding whether to stay open another hour. These are about the
  // shop — stock, pricing, the regular who noticed you cut a corner.
  static const List<DailyQuote> _sellerQuotes = <DailyQuote>[
    DailyQuote(
        'A shop that opens on time earns trust before it earns money.',
        'நேரத்துக்கு திறக்கிற கடை, காசுக்கு முன்னாடி நம்பிக்கையை சம்பாதிக்கும்.'),
    DailyQuote(
        'One happy customer brings four you never advertised to.',
        'ஒரு திருப்தியான வாடிக்கையாளர் நாலு பேரை கூட்டி வருவார்.'),
    DailyQuote(
        'Quality is the cheapest marketing there is.',
        'தரம்தான் மிக மலிவான விளம்பரம்.'),
    DailyQuote(
        'Answer the phone. Half your competition does not.',
        'ஃபோனை எடுங்க — பாதி போட்டியாளர்கள் எடுக்க மாட்டாங்க.'),
    DailyQuote(
        'A clean counter sells more than a big banner.',
        'பெரிய பேனரை விட சுத்தமான கவுண்டர் அதிகம் விற்கும்.'),
    DailyQuote(
        'Never argue with a customer you want to keep.',
        'வைச்சுக்கணும்னு நினைக்கிற வாடிக்கையாளர்கிட்ட வாதம் வேண்டாம்.'),
    DailyQuote(
        'Price honestly today, and you will still be here next year.',
        'இன்னைக்கு நேர்மையா விலை வையுங்க — அடுத்த வருஷமும் இங்கேயே இருப்பீங்க.'),
    DailyQuote(
        'Stock what sells, not what you like.',
        'உங்களுக்கு பிடிச்சதை அல்ல, விற்கிறதை வையுங்க.'),
    DailyQuote(
        'The order you deliver well is your next advertisement.',
        'நல்லா கொடுத்த ஆர்டர்தான் உங்க அடுத்த விளம்பரம்.'),
    DailyQuote(
        'Count the stock before the stock counts you.',
        'ஸ்டாக்கை நீங்க எண்ணுங்க, இல்லைனா அது உங்களை எண்ணும்.'),
    DailyQuote(
        'A small shop with a big name beats a big shop with none.',
        'பெயர் இருக்கிற சின்ன கடை, பெயர் இல்லாத பெரிய கடையை விட மேல்.'),
    DailyQuote(
        'Say no clearly instead of yes carelessly.',
        'கவனமில்லாத \'ஆம்\' விட, தெளிவான \'இல்லை\' மேல்.'),
    DailyQuote(
        'Update your menu before a customer finds it wrong.',
        'வாடிக்கையாளர் கண்டுபிடிக்கிறதுக்கு முன்னாடி மெனுவை சரி பண்ணுங்க.'),
    DailyQuote(
        'Profit hides in the items you forgot to price right.',
        'சரியா விலை வைக்காத பொருள்லதான் லாபம் ஒளிஞ்சிருக்கு.'),
    DailyQuote(
        'Serve the regular as well as you served them the first day.',
        'பழைய வாடிக்கையாளரையும் முதல் நாள் மாதிரியே கவனிங்க.'),
    DailyQuote(
        'A shop is a promise you keep every single day.',
        'கடை என்பது தினமும் காக்கிற ஒரு வாக்குறுதி.'),
    DailyQuote(
        'Waste less today and you have earned more today.',
        'இன்னைக்கு வீணடிக்காம இருந்தா, இன்னைக்கே சம்பாதிச்சாச்சு.'),
    DailyQuote(
        'Your staff treat customers the way you treat your staff.',
        'நீங்க வேலையாட்களை நடத்துற மாதிரிதான் அவங்க வாடிக்கையாளரை நடத்துவாங்க.'),
    DailyQuote(
        'Close the shop tired, not angry.',
        'களைப்போட கடையை மூடுங்க, கோபத்தோட இல்லை.'),
    DailyQuote(
        'The complaint you fix today is the customer you keep for years.',
        'இன்னைக்கு சரி பண்ற புகார், வருஷக்கணக்கா தங்குற வாடிக்கையாளர்.'),
    DailyQuote(
        'Good photos sell food you already cook well.',
        'நல்ல படம் இருந்தா, நீங்க ஏற்கனவே நல்லா சமைக்கிறது விற்கும்.'),
    DailyQuote(
        'Do not chase every customer. Serve the ones who came.',
        'எல்லாரையும் துரத்தாதீங்க — வந்தவங்களை நல்லா கவனிங்க.'),
    DailyQuote(
        'A fair weight builds a shop nobody can copy.',
        'நேர்மையான எடை, யாரும் காப்பி பண்ண முடியாத கடையை கட்டும்.'),
    DailyQuote(
        'Delivery on time is a taste of its own.',
        'நேரத்துக்கு டெலிவரி — அதுவே ஒரு ருசி.'),
    DailyQuote(
        'Learn one thing from every order that went wrong.',
        'தப்பான ஒவ்வொரு ஆர்டர்லயும் ஒண்ணு கத்துக்குங்க.'),
    DailyQuote(
        'The market changes. Your standards should not.',
        'சந்தை மாறும் — உங்க தரம் மாறக்கூடாது.'),
    DailyQuote(
        'Keep the shop open a little longer on a good day.',
        'நல்ல நாள்ல கொஞ்சம் நேரம் அதிகமா கடையை திறந்து வையுங்க.'),
    DailyQuote(
        'Your best seller today was somebody\'s experiment last year.',
        'இன்னைக்கு அதிகம் விற்கிறது, போன வருஷம் ஒரு முயற்சி.'),
    DailyQuote(
        'Talk to the customer who left without buying.',
        'வாங்காம போனவங்ககிட்ட ஒரு வார்த்தை பேசுங்க.'),
    DailyQuote(
        'A written price ends ten arguments.',
        'எழுதின விலை பத்து வாதத்தை முடிக்கும்.'),
    DailyQuote(
        'Grow slowly enough to keep the quality.',
        'தரம் காக்கிற வேகத்துல வளருங்க.'),
    DailyQuote(
        'The shop next door is not your enemy. Boredom is.',
        'பக்கத்து கடை எதிரி இல்லை — சலிப்புதான்.'),
    DailyQuote(
        'Every rupee saved on waste is a rupee earned twice.',
        'வீணை தவிர்த்த ஒவ்வொரு ரூபாயும் இரண்டு முறை சம்பாதிச்சது.'),
    DailyQuote(
        'Say thank you like you mean it, because you do.',
        'மனசார நன்றி சொல்லுங்க — அதுதான் உண்மை.'),
    DailyQuote(
        'A shop with a story outlives a shop with a sale.',
        'கதை இருக்கிற கடை, தள்ளுபடி இருக்கிற கடையை விட நீடிக்கும்.'),
    DailyQuote(
        'Check tomorrow\'s stock before you sleep tonight.',
        'இன்னைக்கு தூங்குறதுக்கு முன்னாடி நாளைய ஸ்டாக்கை பாருங்க.'),
    DailyQuote(
        'You are not selling items. You are selling reliability.',
        'நீங்க பொருள் விற்கல — நம்பகத்தன்மையை விற்குறீங்க.'),
    DailyQuote(
        'The rush will pass. Your reputation will not.',
        'கூட்டம் கலையும் — உங்க பெயர் கலையாது.'),
    DailyQuote(
        'Reply fast, even to say you are busy.',
        'பிசியா இருக்கீங்கனு சொல்லவாவது சீக்கிரம் பதில் சொல்லுங்க.'),
    DailyQuote(
        'A shop that listens never needs to shout.',
        'கேட்கிற கடை கத்த வேண்டியதில்லை.'),
    DailyQuote(
        'Give a little extra when nobody asked.',
        'யாரும் கேட்காதப்போ கொஞ்சம் அதிகமா கொடுங்க.'),
    DailyQuote(
        'Your worst day teaches more than your best week.',
        'மோசமான நாள், சிறந்த வாரத்தை விட அதிகம் கத்துக்கொடுக்கும்.'),
    DailyQuote(
        'Build the shop your family would be proud to run.',
        'உங்க குடும்பம் பெருமைப்படுற கடையை கட்டுங்க.'),
    DailyQuote(
        'Weigh right even when nobody is watching.',
        'யாரும் பாக்கலைனாலும் சரியா எடை போடுங்க.'),
    DailyQuote(
        'The customer who bargains hardest often returns most.',
        'அதிகம் பேரம் பேசுறவங்கதான் அதிகம் திரும்ப வருவாங்க.'),
    DailyQuote(
        'Label everything. Confusion costs money.',
        'எல்லாத்துக்கும் லேபிள் போடுங்க — குழப்பம் காசு.'),
    DailyQuote(
        'Your shop smells like your standards.',
        'உங்க கடையோட வாசனையே உங்க தரம்.'),
    DailyQuote(
        'Do not sell today what you would not eat tonight.',
        'இன்னைக்கு ராத்திரி நீங்க சாப்பிடாததை விற்காதீங்க.'),
    DailyQuote(
        'Train one person to replace you for a day.',
        'ஒரு நாளைக்கு உங்க இடத்துல நிக்க ஒருத்தரை பழக்குங்க.'),
    DailyQuote(
        'A shop that is never closed is never trusted either.',
        'எப்பவும் திறந்திருக்கிற கடையையும் யாரும் நம்ப மாட்டாங்க — ஓய்வும் தேவை.'),
    DailyQuote(
        'Photograph the food before it cools.',
        'ஆறுறதுக்கு முன்னாடி சாப்பாட்டை படம் எடுங்க.'),
    DailyQuote(
        'Sell out early rather than throw away late.',
        'தாமதமா வீணடிக்கிறதை விட சீக்கிரம் விற்று முடிங்க.'),
    DailyQuote(
        'The regular customer notices the day you cut corners.',
        'நீங்க சமரசம் பண்ற நாளை பழைய வாடிக்கையாளர் கண்டுபிடிப்பார்.'),
    DailyQuote(
        'Write your prices bigger than your discounts.',
        'தள்ளுபடியை விட விலையை பெரிசா எழுதுங்க.'),
    DailyQuote(
        'Give change with both hands and a thank you.',
        'இரண்டு கையால சில்லறை கொடுங்க, ஒரு நன்றியோட.'),
    DailyQuote(
        'Your best staff member is the one customers ask for.',
        'வாடிக்கையாளர் பேர் சொல்லி கேக்குறவர்தான் உங்க சிறந்த ஊழியர்.'),
    DailyQuote(
        'A shop without a rest day burns out its owner.',
        'ஓய்வு நாள் இல்லாத கடை, முதலாளியை தீர்த்துடும்.'),
    DailyQuote(
        'Fix the price list before the festival rush.',
        'பண்டிகை கூட்டத்துக்கு முன்னாடி விலை பட்டியலை சரி பண்ணுங்க.'),
    DailyQuote(
        'The customer is not always right, but they are always the customer.',
        'வாடிக்கையாளர் எப்பவும் சரி இல்ல — ஆனா எப்பவும் வாடிக்கையாளர்தான்.'),
    DailyQuote(
        'Keep one item cheap so everyone can walk in.',
        'எல்லாரும் உள்ள வர ஒரு பொருளை மலிவா வையுங்க.'),
    DailyQuote(
        'Note down what you ran out of today.',
        'இன்னைக்கு தீர்ந்து போனதை எழுதி வையுங்க.'),
    DailyQuote(
        'Deliver the order you promised, not the one that is easier.',
        'சுலபமானதை அல்ல, சொன்ன ஆர்டரை கொடுங்க.'),
    DailyQuote(
        'Talk to your supplier before your stock talks to you.',
        'ஸ்டாக் பேசுறதுக்கு முன்னாடி சப்ளையர்கிட்ட பேசுங்க.'),
    DailyQuote(
        'A neat bill ends the day peacefully.',
        'நேர்த்தியான கணக்கு, நாளை நிம்மதியா முடிக்கும்.'),
    DailyQuote(
        'Copy the shop you admire, then do one thing better.',
        'பிடிச்ச கடையை பாருங்க — ஒரு விஷயத்தை மட்டும் இன்னும் நல்லா செய்யுங்க.'),
    DailyQuote(
        'Do not blame the season. Change the offer.',
        'காலத்தை குறை சொல்லாதீங்க — ஆஃபரை மாத்துங்க.'),
    DailyQuote(
        'The item you push hardest should be the one you make best.',
        'நீங்க அதிகம் விற்க நினைக்கிறது, நீங்க சிறப்பா செய்யிறதா இருக்கணும்.'),
    DailyQuote(
        'Answer the bad review politely. Everyone is reading it.',
        'மோசமான விமர்சனத்துக்கு பணிவா பதில் சொல்லுங்க — எல்லாரும் படிக்கிறாங்க.'),
    DailyQuote(
        'Stock a little extra on payday week.',
        'சம்பள வாரத்துல கொஞ்சம் அதிகமா ஸ்டாக் வையுங்க.'),
    DailyQuote(
        'A shop is judged by its worst day, not its best.',
        'சிறந்த நாள் இல்லை — மோசமான நாள்தான் கடையை தீர்மானிக்கும்.'),
    DailyQuote(
        'Serve the child in the queue like an adult.',
        'வரிசைல நிக்கிற குழந்தையையும் பெரியவர் மாதிரி கவனிங்க.'),
    DailyQuote(
        'Keep your promise about time above your promise about price.',
        'விலை வாக்குறுதியை விட நேர வாக்குறுதியை காப்பாத்துங்க.'),
    DailyQuote(
        'Every complaint is free consulting.',
        'ஒவ்வொரு புகாரும் இலவச ஆலோசனை.'),
    DailyQuote(
        'Sell what your street needs, not what the city trends.',
        'நகர டிரெண்டை அல்ல, உங்க தெருவுக்கு தேவையானதை விற்குங்க.'),
    DailyQuote(
        'You built this shop. Do not let one bad day rename it.',
        'இந்த கடையை நீங்க கட்டினீங்க — ஒரு மோசமான நாள் அதை மாத்த விடாதீங்க.'),
  ];

  // ── ADMIN POOL ─────────────────────────────────────────────────
  // The owner's own pool. Written for someone who can see every queue
  // and has to decide which one to open first — not for someone who
  // needs cheering up.
  static const List<DailyQuote> _adminQuotes = <DailyQuote>[
    DailyQuote(
        'Look at the numbers before you look at the opinions.',
        'கருத்துக்களுக்கு முன்னாடி கணக்கை பாருங்க.'),
    DailyQuote(
        'A queue you clear today is a customer you keep this year.',
        'இன்னைக்கு காலி பண்ற வரிசை, இந்த வருஷம் தங்குற வாடிக்கையாளர்.'),
    DailyQuote(
        'Approve fast or reject clearly. Silence costs the most.',
        'வேகமா ஒப்புதல், இல்லைனா தெளிவா மறுப்பு — மௌனம்தான் விலை அதிகம்.'),
    DailyQuote(
        'Every unread report is a decision you already made.',
        'படிக்காத ஒவ்வொரு ரிப்போர்ட்டும் நீங்க ஏற்கனவே எடுத்த முடிவு.'),
    DailyQuote(
        'Fix the process, not the person.',
        'நபரை அல்ல, முறையை சரி பண்ணுங்க.'),
    DailyQuote(
        'The bug reported twice will be reported twenty times.',
        'இரண்டு முறை சொன்ன பிழை, இருபது முறை வரும்.'),
    DailyQuote(
        'A platform is only as good as its slowest queue.',
        'மெதுவான வரிசை எவ்வளவோ, தளமும் அவ்வளவுதான்.'),
    DailyQuote(
        'Trust the seller who tells you bad news early.',
        'மோசமான செய்தியை முன்னாடியே சொல்ற விற்பனையாளரை நம்புங்க.'),
    DailyQuote(
        'Cost control is a daily habit, not a yearly meeting.',
        'செலவு கட்டுப்பாடு தினசரி பழக்கம் — வருஷ கூட்டம் இல்லை.'),
    DailyQuote(
        'Your heroes are your product. Look after them.',
        'உங்க ஹீரோக்கள்தான் உங்க தயாரிப்பு — அவங்களை கவனிங்க.'),
    DailyQuote(
        'Read one customer complaint fully today.',
        'இன்னைக்கு ஒரு புகாரை முழுசா படிங்க.'),
    DailyQuote(
        'Growth without quality is just a bigger problem.',
        'தரம் இல்லாத வளர்ச்சி, பெரிய பிரச்சனைதான்.'),
    DailyQuote(
        'Decide today. A late right answer is a wrong answer.',
        'இன்னைக்கே முடிவு பண்ணுங்க — தாமதமான சரி, தப்புதான்.'),
    DailyQuote(
        'The data tells you what. Talk to people to learn why.',
        'தரவு \'என்ன\'னு சொல்லும் — \'ஏன்\'னு தெரிய மனிதர்கிட்ட பேசுங்க.'),
    DailyQuote(
        'Protect the free tier. Every read has a price.',
        'இலவச வரம்பை காப்பாத்துங்க — ஒவ்வொரு படிப்புக்கும் விலை உண்டு.'),
    DailyQuote(
        'A rule nobody can explain is a rule nobody will follow.',
        'விளக்க முடியாத விதியை யாரும் பின்பற்ற மாட்டாங்க.'),
    DailyQuote(
        'Reward the seller who never made the news.',
        'பேச்சுக்கே வராத விற்பனையாளரை பாராட்டுங்க.'),
    DailyQuote(
        'Small daily fixes beat one big rewrite.',
        'ஒரு பெரிய மாற்றத்தை விட, தினசரி சின்ன சரிசெய்தல் மேல்.'),
    DailyQuote(
        'Answer the enquiry while the customer still cares.',
        'வாடிக்கையாளருக்கு ஆர்வம் இருக்கும்போதே பதில் சொல்லுங்க.'),
    DailyQuote(
        'If it is not measured, it is somebody\'s guess.',
        'அளக்கலைனா, அது யாரோட ஊகம்தான்.'),
    DailyQuote(
        'Say no to the feature that serves nobody in Erode.',
        'ஈரோட்ல யாருக்கும் உதவாத அம்சத்துக்கு \'இல்லை\' சொல்லுங்க.'),
    DailyQuote(
        'A tired team ships bugs. Send them home.',
        'களைச்ச டீம் பிழை கொடுக்கும் — வீட்டுக்கு அனுப்புங்க.'),
    DailyQuote(
        'The founder who answers support learns fastest.',
        'சப்போர்ட்டுக்கு பதில் சொல்ற நிறுவனர்தான் வேகமா கத்துக்குவார்.'),
    DailyQuote(
        'Every rupee saved on servers is a rupee for growth.',
        'சர்வர்ல மிச்சம் பண்ற ஒவ்வொரு ரூபாயும் வளர்ச்சிக்கு.'),
    DailyQuote(
        'Approve the hero today. They have rent tomorrow.',
        'இன்னைக்கே ஹீரோவை அப்ரூவ் பண்ணுங்க — நாளைக்கு அவங்களுக்கு வாடகை.'),
    DailyQuote(
        'A dashboard nobody opens is decoration.',
        'யாரும் திறக்காத டாஷ்போர்டு வெறும் அலங்காரம்.'),
    DailyQuote(
        'Write the reason down. Future you will ask.',
        'காரணத்தை எழுதி வையுங்க — நாளைய நீங்க கேட்பீங்க.'),
    DailyQuote(
        'Your best feature is the one that never fails.',
        'எப்பவும் தோக்காத அம்சம்தான் உங்க சிறந்த அம்சம்.'),
    DailyQuote(
        'Listen to the seller who wants to leave.',
        'வெளியேற நினைக்கிற விற்பனையாளர்கிட்ட கேளுங்க.'),
    DailyQuote(
        'Ship small, ship often, sleep well.',
        'சின்னதா, அடிக்கடி வெளியிடுங்க — நிம்மதியா தூங்குங்க.'),
    DailyQuote(
        'The city you serve is the boss you answer to.',
        'நீங்க சேவை செய்ற நகரம்தான் உங்க முதலாளி.'),
    DailyQuote(
        'Do the boring maintenance before it becomes an outage.',
        'பழுதாகுறதுக்கு முன்னாடி சலிப்பான பராமரிப்பை செய்யுங்க.'),
    DailyQuote(
        'One clear metric beats ten pretty charts.',
        'பத்து அழகான சார்ட்டை விட ஒரு தெளிவான அளவீடு மேல்.'),
    DailyQuote(
        'Praise in public, correct in private.',
        'பொதுவா பாராட்டுங்க, தனியா திருத்துங்க.'),
    DailyQuote(
        'Your platform\'s reputation is built at 11pm, not at launch.',
        'தளத்தோட பெயர் அறிமுகத்துல இல்ல — இரவு 11 மணிக்குதான் கட்டப்படும்.'),
    DailyQuote(
        'Check the free quota before the month checks it for you.',
        'மாசம் முடியுறதுக்கு முன்னாடி இலவச வரம்பை பாருங்க.'),
    DailyQuote(
        'A refund given fast costs less than a review given slow.',
        'வேகமா கொடுக்கிற பணம், மெதுவா வர்ற விமர்சனத்தை விட மலிவு.'),
    DailyQuote(
        'Build for the customer who has one bar of signal.',
        'ஒரு கோடு சிக்னல் இருக்கிற வாடிக்கையாளருக்காக கட்டுங்க.'),
    DailyQuote(
        'The hardest queue is the one you stopped looking at.',
        'நீங்க பாக்குறதை நிறுத்தின வரிசைதான் கஷ்டமானது.'),
    DailyQuote(
        'Delegate the task, not the responsibility.',
        'வேலையை பகிருங்க — பொறுப்பை இல்லை.'),
    DailyQuote(
        'Erode is not a test market. It is the market.',
        'ஈரோடு சோதனை சந்தை இல்ல — அதுதான் சந்தை.'),
    DailyQuote(
        'Today\'s small decision compounds into next year\'s company.',
        'இன்னைய சின்ன முடிவுதான் அடுத்த வருஷ நிறுவனம்.'),
    DailyQuote(
        'If the founder will not use it, do not ship it.',
        'நிறுவனரே உபயோகிக்க மாட்டார்னா, அதை வெளியிடாதீங்க.'),
    DailyQuote(
        'Open the app as a customer once a week.',
        'வாரம் ஒரு முறை வாடிக்கையாளரா ஆப்பை திறங்க.'),
    DailyQuote(
        'A metric without a decision attached is noise.',
        'முடிவு இல்லாத அளவீடு வெறும் சத்தம்.'),
    DailyQuote(
        'Call one hero today and just listen.',
        'இன்னைக்கு ஒரு ஹீரோவுக்கு கால் பண்ணி கேளுங்க — பேசாதீங்க.'),
    DailyQuote(
        'The cheapest fix is the one you do before launch.',
        'வெளியிடுறதுக்கு முன்னாடி செய்யிற திருத்தம்தான் மலிவானது.'),
    DailyQuote(
        'Do not add a feature to hide a broken one.',
        'உடைஞ்ச அம்சத்தை மறைக்க புது அம்சம் சேர்க்காதீங்க.'),
    DailyQuote(
        'Approve, reject, or explain. Never leave it open.',
        'ஒப்புங்க, மறுங்க, இல்லைனா விளக்குங்க — திறந்தே விடாதீங்க.'),
    DailyQuote(
        'A platform is trust rendered as software.',
        'தளம் என்பது மென்பொருளா மாறின நம்பிக்கை.'),
    DailyQuote(
        'Read your own error messages out loud.',
        'உங்க பிழைச் செய்திகளை சத்தமா படிங்க.'),
    DailyQuote(
        'The seller\'s problem today is your churn next month.',
        'இன்னைக்கு விற்பனையாளர் பிரச்சனை, அடுத்த மாசம் உங்க நஷ்டம்.'),
    DailyQuote(
        'Backups you never restored are not backups.',
        'திரும்ப பெறாத பேக்கப் — பேக்கப்பே இல்ல.'),
    DailyQuote(
        'Cut the report nobody reads.',
        'யாரும் படிக்காத ரிப்போர்ட்டை நிறுத்துங்க.'),
    DailyQuote(
        'A slow screen is a lost customer with better manners.',
        'மெதுவான ஸ்கிரீன், பணிவா விலகுற வாடிக்கையாளர்.'),
    DailyQuote(
        'Decide with the data you have, not the data you want.',
        'வேணும்னு நினைக்கிற தரவு இல்ல — இருக்கிற தரவு வெச்சு முடிவு பண்ணுங்க.'),
    DailyQuote(
        'Hire slowly for attitude. Teach the rest.',
        'மனப்பான்மைக்காக மெதுவா ஆள் எடுங்க — மீதி கத்துக்கொடுக்கலாம்.'),
    DailyQuote(
        'Your on-call phone is your real product review.',
        'உங்க ஆன்-கால் ஃபோன்தான் நிஜமான விமர்சனம்.'),
    DailyQuote(
        'Simplify one screen this week.',
        'இந்த வாரம் ஒரு ஸ்கிரீனை எளிமையாக்குங்க.'),
    DailyQuote(
        'The competitor is not the threat. Complacency is.',
        'போட்டியாளர் அச்சுறுத்தல் இல்ல — திருப்தியே ஆபத்து.'),
    DailyQuote(
        'Pay your people before you pay for ads.',
        'விளம்பரத்துக்கு முன்னாடி உங்க ஆட்களுக்கு கொடுங்க.'),
    DailyQuote(
        'Every permission you grant is a risk you accepted.',
        'நீங்க கொடுக்கிற ஒவ்வொரு அனுமதியும் ஏத்துக்கிட்ட ஆபத்து.'),
    DailyQuote(
        'Test on the cheapest phone you can find.',
        'கிடைக்கிற மலிவான ஃபோன்ல சோதிங்க.'),
    DailyQuote(
        'A founder\'s calendar shows the company\'s priorities.',
        'நிறுவனரோட காலண்டர்தான் நிறுவனத்தோட முன்னுரிமை.'),
    DailyQuote(
        'Do the unglamorous work. That is where the moat is.',
        'கவர்ச்சி இல்லாத வேலையை செய்யுங்க — அங்கதான் பலம்.'),
    DailyQuote(
        'Ask why three times before you build.',
        'கட்டுறதுக்கு முன்னாடி மூணு முறை \'ஏன்\'னு கேளுங்க.'),
    DailyQuote(
        'A good policy is one sentence long.',
        'நல்ல கொள்கை ஒரு வாக்கியம்தான்.'),
    DailyQuote(
        'Watch the drop-off, not the sign-ups.',
        'பதிவை அல்ல, விலகலை கவனிங்க.'),
    DailyQuote(
        'Your worst reviewer is your cheapest consultant.',
        'உங்க மோசமான விமர்சகர்தான் மலிவான ஆலோசகர்.'),
    DailyQuote(
        'Keep one day a week free to think.',
        'வாரத்துல ஒரு நாள் யோசிக்க ஒதுக்குங்க.'),
    DailyQuote(
        'Say the hard thing early and kindly.',
        'கஷ்டமான விஷயத்தை முன்னாடியே, அன்பா சொல்லுங்க.'),
    DailyQuote(
        'An outage handled well earns more trust than uptime.',
        'நல்லா கையாண்ட செயலிழப்பு, தொடர்ச்சியை விட நம்பிக்கை தரும்.'),
    DailyQuote(
        'Document it once instead of explaining it ten times.',
        'பத்து முறை விளக்குறதை விட ஒரு முறை எழுதுங்க.'),
    DailyQuote(
        'Your first thousand customers deserve a phone call.',
        'உங்க முதல் ஆயிரம் வாடிக்கையாளருக்கு ஒரு கால் கடமை.'),
    DailyQuote(
        'Build the boring thing that never needs you again.',
        'திரும்ப உங்களை தேவைப்படாத சலிப்பான விஷயத்தை கட்டுங்க.'),
  ];

}
