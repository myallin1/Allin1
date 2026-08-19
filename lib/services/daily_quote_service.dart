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
  /// [languageCode] comes from LocalizationService; anything that isn't
  /// Tamil falls back to English, including 'tanglish' — a Tanglish
  /// reader is by definition comfortable with the Latin script.
  String forCustomer(String languageCode, {DateTime? now}) =>
      _text(_pick(_customerQuotes, now ?? DateTime.now()), languageCode);

  /// Today's line for a HERO. A separate pool on purpose: a hero opens
  /// this app to earn, often early, often tired, and a generic "believe
  /// in yourself" reads as hollow next to a line about the work itself.
  String forHero(String languageCode, {DateTime? now}) =>
      _text(_pick(_heroQuotes, now ?? DateTime.now()), languageCode);

  static String _text(DailyQuote q, String languageCode) =>
      languageCode == 'ta' ? q.ta : q.en;

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
  ];
}
