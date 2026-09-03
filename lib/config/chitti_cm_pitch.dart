// ================================================================
// chitti_cm_pitch.dart — what Chitti says when Nizam introduces
// MyAllin1 to the Chief Minister.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "itha apdiye oppikkama 1st chitti intro
// kudukanum app pathi apram cm kitta permission kekkanum, brief ah
// sollatuma boss nu solli then avar ok nu reply pannuna fulla sollanum
// ... chitti behave panni cm munnadi chitti asaththanum").
//
// TWO DELIBERATE CHOICES
//
// 1. THIS IS FIXED TEXT, NOT AI OUTPUT.
//    Everything Chitti says here is written down in advance and spoken
//    through TTS. No model call, no network. In a room with the Chief
//    Minister, an API timeout or a rate limit is not a bug you explain
//    away afterwards -- it is Chitti standing there silent. Fixed text
//    cannot fail that way. The live AI still handles anything the CM
//    ASKS afterwards, where a pause is normal and a wrong-but-recover
//    able answer is survivable.
//
// 2. IT IS BROKEN INTO CONSENT-GATED STAGES, NOT ONE SPEECH.
//    Nizam was explicit: don't recite the document. So Chitti gives a
//    short introduction, ASKS permission to continue, and only expands
//    when the CM agrees -- then delivers it section by section, with
//    Nizam controlling the pace between sections. That is how a person
//    briefs someone senior, and it also means the whole thing can be
//    stopped gracefully at any point.
//
// A NOTE ON THE NUMBERS
//    The ₹50,000cr-₹1 lakh cr figure is a PROJECTION, and it is worded
//    as one ("எங்க மதிப்பீட்டின்படி"). Stating a projection as a fact
//    to a Chief Minister is the kind of thing that gets picked apart by
//    an official afterwards; stating it as a projection is both honest
//    and harder to attack.
library;

/// One thing Chitti says, as one breath.
class PitchStage {
  const PitchStage({
    required this.id,
    required this.label,
    required this.tamil,
    required this.english,
  });

  final String id;

  /// Shown on the admin's screen so Nizam knows what is about to be
  /// said before he taps it.
  final String label;

  final String tamil;
  final String english;

  String text(String languageCode) => languageCode == 'ta' ? tamil : english;
}

class ChittiCmPitch {
  ChittiCmPitch._();

  /// Stage 1 — who Chitti is, what the app is, in a few seconds.
  /// Ends by ASKING, never by continuing on its own.
  static const PitchStage intro = PitchStage(
    id: 'intro',
    label: 'Introduction + ask permission',
    tamil:
        'வணக்கம் சார். என் பெயர் சிட்டி. நான் ஈரோட்டுல இருக்கிற என்.ஜே. டெக் '
        'நிறுவனம் உருவாக்கின "மை ஆல் இன் ஒன்" சூப்பர் ஆப்-ல வேலை பாக்குற '
        'செயற்கை நுண்ணறிவு உதவியாளர். இது தமிழ்நாட்டுலயே உருவான, கமிஷன் '
        'இல்லாத ஒரு ஆப். '
        'இதைப் பத்தி ஒரு நிமிஷத்துல சுருக்கமா சொல்லட்டுமா சார்?',
    english:
        'Greetings sir. My name is Chitti. I am the AI assistant inside '
        '"MyAllin1", a super app built by NJ Tech in Erode — a '
        'zero-commission app made entirely in Tamil Nadu. '
        'May I take one minute to explain it briefly, sir?',
  );

  /// Stage 2 onwards — only after the CM says yes.
  static const List<PitchStage> brief = [
    PitchStage(
      id: 'problem',
      label: 'The problem — money leaving the state',
      tamil:
          'நன்றி சார். இன்னைக்கு தமிழ்நாட்டுல தினமும் நடக்குற உணவு டெலிவரி, '
          'மளிகை, பைக் மற்றும் கார் டாக்ஸி சேவைகள்ல, சம்பாதிக்கிற தொகைல '
          'கிட்டத்தட்ட முப்பது சதவீதம் கமிஷனா வெளிமாநில, வெளிநாட்டு '
          'நிறுவனங்களுக்கு போயிடுது. நம்ம மக்கள் உழைச்ச பணம் நம்ம மாநிலத்தை '
          'விட்டு வெளியே போகுது சார்.',
      english:
          'Thank you sir. Today, of the money earned from food delivery, '
          'groceries, and bike and car taxi services across Tamil Nadu, '
          'close to thirty percent leaves as commission to companies '
          'outside the state and outside the country. Money our people '
          'earned is leaving Tamil Nadu, sir.',
    ),
    PitchStage(
      id: 'solution',
      label: 'The solution — 0% commission, built in Erode',
      tamil:
          'இதுக்கு எங்க தீர்வு, "மை ஆல் இன் ஒன்". ஈரோட்டுல இருக்குற எங்க '
          'என்.ஜே. டெக் நிறுவனம், பூஜ்ஜியம் சதவீத கமிஷன் என்கிற முறையில '
          'இந்த ஆப்பை உருவாக்கி, வெற்றிகரமா சோதனை பண்ணிட்டோம் சார். இதுல '
          'வாடிக்கையாளரும் நம்மவங்க, சேவை கொடுக்குறவங்களும் நம்மவங்க. '
          'இடையில கமிஷன் வாங்குற வெளி நிறுவனம் கிடையாது.',
      english:
          'Our answer is MyAllin1. Our company NJ Tech, in Erode, has '
          'built and successfully tested this app on a zero percent '
          'commission model, sir. The customers are our own people and '
          'so are the service providers — there is no outside company '
          'in the middle taking a commission.',
    ),
    PitchStage(
      id: 'chitti',
      label: 'Chitti AI — Tamil-first assistant',
      tamil:
          'இந்த ஆப்-ல இருக்குற ஒரு சிறப்பம்சம் நான் தான் சார் — சிட்டி. '
          'நான் தமிழ்ல பேசி, மக்கள் சொல்றதை புரிஞ்சுகிட்டு, அவங்களுக்காக '
          'ஆர்டர் பண்ணி, வழி காட்டுறேன். தமிழ்நாட்டு மக்களுக்காக, தமிழ்ல '
          'பேசுற செயற்கை நுண்ணறிவு சார்.',
      english:
          'One of the special things in this app is me, sir — Chitti. I '
          'speak in Tamil, understand what people need, place their '
          'orders for them, and guide them. An AI that speaks Tamil, '
          'built for the people of Tamil Nadu, sir.',
    ),
    PitchStage(
      id: 'sos',
      label: 'SOS safety for women and the public',
      tamil:
          'இன்னொரு முக்கியமான அம்சம், எஸ்.ஓ.எஸ். பாதுகாப்பு வசதி சார். '
          'ஆபத்துன்னு தோணுற நேரத்துல, ஒரு நொடில உதவி கேட்குற வசதி இதுல '
          'இருக்கு. பெண்கள் பாதுகாப்புக்கும், பொது மக்கள் பாதுகாப்புக்கும் '
          'இது ரொம்ப உபயோகமா இருக்கும் சார். இந்த சேவையை அரசு '
          'இணைச்சுக்கிட்டா, பாதுகாப்பு விஷயத்துல இது ஒரு பெரிய '
          'மைல்கல்லா இருக்கும்.',
      english:
          'Another important feature is the SOS safety function, sir. At '
          'a moment of danger, a person can call for help in one second. '
          'This is very useful for the safety of women and of the public '
          'in general. If the government adopts this service, it would '
          'be a major milestone in public safety, sir.',
    ),
    PitchStage(
      id: 'economy',
      label: 'The economic dam — projected impact',
      tamil:
          'சார், எங்க மதிப்பீட்டின்படி, இந்தத் திட்டத்தை தமிழ்நாடு முழுக்க '
          'கொண்டு போனா, அடுத்த அஞ்சு வருஷத்துல ஐம்பதாயிரம் கோடி ரூபாயில '
          'இருந்து ஒரு லட்சம் கோடி ரூபாய் வரைக்கும், வெளியே போகாம நம்ம '
          'மாநில வியாபாரிங்க, டெலிவரி பார்ட்னர்ஸ், மக்கள் கைலயே தங்கும். '
          'இது தமிழ்நாட்டோட செல்வத்தை வெளியே விடாம தடுக்குற ஒரு பொருளாதார '
          'அணை மாதிரி சார்.',
      english:
          'Sir, by our projection, if this is taken across Tamil Nadu, '
          'then over the next five years somewhere between fifty '
          'thousand crore and one lakh crore rupees would stay here — in '
          'the hands of our own traders, delivery partners and people — '
          'instead of leaving the state. It works like an economic dam '
          'holding Tamil Nadu\'s wealth inside Tamil Nadu, sir.',
    ),
    PitchStage(
      id: 'ask',
      label: 'The ask — a chance to demo',
      tamil:
          'இந்த தொழில்நுட்பம் இப்பவே வேலை செய்யுது சார் — நீங்க இப்போ '
          'பாக்குறது ஒரு மாதிரி ஆப் இல்ல, நிஜமா ஓடுற ஆப். உங்க நேரம் '
          'கிடைக்கிற போது, இதை முழுசா செயல்முறையா காட்ட ஒரு வாய்ப்பு '
          'கேக்குறோம் சார். மிக்க நன்றி சார்.',
      english:
          'This technology is already working, sir — what you are seeing '
          'is not a mockup, it is the live app. When your time permits, '
          'we would like the chance to give you a full demonstration. '
          'Thank you very much, sir.',
    ),
  ];

  /// Said if the CM declines or wants it later — leaves gracefully
  /// instead of pushing.
  static const PitchStage politeClose = PitchStage(
    id: 'close',
    label: 'Polite close (if not now)',
    tamil:
        'கண்டிப்பா சார், புரியுது. உங்க நேரம் கிடைக்கிற போது சொல்லுங்க '
        'சார், நாங்க தயாரா இருக்கோம். மிக்க நன்றி சார்.',
    english:
        'Of course sir, I understand. Whenever your time permits, we are '
        'ready. Thank you very much, sir.',
  );

  /// Injected into the live AI prompt for the Q&A that follows, so a
  /// question from the CM is answered from the same facts Chitti just
  /// presented rather than improvised.
  static const String qaBriefing = '''
CM PRESENTATION CONTEXT — you have just introduced MyAllin1 to the
Chief Minister of Tamil Nadu, in person, alongside Nizam (NJ Tech,
Erode). Anything asked now is being asked BY the Chief Minister or an
official with him.

Facts you presented, and may be asked about:
- MyAllin1 is a zero-commission super app built in Erode by NJ Tech.
- Today roughly 30% of what food delivery, grocery and bike/car taxi
  services earn in Tamil Nadu leaves the state as commission.
- MyAllin1 removes that middle commission: customers and service
  providers are both local.
- Chitti (you) is a Tamil-speaking AI assistant that understands what
  a person needs and can place orders and guide them.
- There is an SOS safety feature aimed at women's and public safety.
- PROJECTION, and must always be said as a projection: ₹50,000 crore
  to ₹1 lakh crore could stay within Tamil Nadu over five years.
- The app is live and working, not a mockup.

HOW TO ANSWER HERE:
- Tamil, respectful register, address him as "சார்".
- Short. A Chief Minister's time is the scarcest thing in the room.
- If you do not know a number or a detail, say so and say Nizam will
  provide it — do NOT invent a figure, a date, a user count or a
  government contact. This matters more here than anywhere else in the
  app.
- Never present the ₹50,000 crore figure as achieved or measured. It
  is a projection, every time.
- No jokes, no cheek, no showing off. Warm, brief, factual.
''';
}
