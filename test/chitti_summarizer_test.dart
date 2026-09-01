import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_summarizer.dart';

void main() {
  group('ChittiSummarizer Token Redaction', () {
    test('masks 4 to 8 digit OTP and PIN numbers', () {
      final input = 'Your OTP for Axis Bank is 492019. Do not share.';
      final redacted = ChittiSummarizer.redactSensitiveTokens(input);
      expect(redacted, contains('[REDACTED]'));
      expect(redacted, isNot(contains('492019')));
    });

    test('masks UPI reference numbers and PIN codes', () {
      final input = 'Paid Rs 500 UPI ref 98765432 and PIN 1234';
      final redacted = ChittiSummarizer.redactSensitiveTokens(input);
      expect(redacted, isNot(contains('98765432')));
      expect(redacted, isNot(contains('1234')));
    });
  });

  group('ChittiSummarizer Heuristic Summaries', () {
    test('summarizes bank OTPs without quoting numbers', () {
      final summary = ChittiSummarizer.heuristicSummary(
        sender: 'HDFC-BANK',
        message: 'Your verification OTP code is 987654. Valid for 10 mins.',
        isTamil: true,
      );
      expect(summary, contains('பரிவர்த்தனை அல்லது OTP அறிவிப்பு'));
      expect(summary, isNot(contains('987654')));
    });

    test('summarizes delivery and order delay inquiries', () {
      final summary = ChittiSummarizer.heuristicSummary(
        sender: 'Ravi',
        message: 'delivery romba late aagudhu, enga irukinga?',
        isTamil: true,
      );
      expect(summary, contains('Ravi'));
      expect(summary, contains('டெலிவரி அல்லது ஆர்டர் நிலை குறித்து கேட்டுள்ளார்'));
    });

    test('summarizes gadget repair inquiries', () {
      final summary = ChittiSummarizer.heuristicSummary(
        sender: 'Kumar',
        message: 'Samsung mobile display change panna evlo aagum bro?',
        isTamil: true,
      );
      expect(summary, contains('Kumar'));
      expect(summary, contains('விலை அல்லது கட்டண விபரம் கேட்டுள்ளார்'));
    });

    test('summarizes ride and transport requests', () {
      final summary = ChittiSummarizer.heuristicSummary(
        sender: 'Priya',
        message: 'Railway station poga auto kedaikuma?',
        isTamil: false,
      );
      expect(summary, contains('Priya'));
      expect(summary, contains('ride or transport booking'));
    });

    test('masks bare numeric tokens in general fallback messages with no keywords', () {
      final summary = ChittiSummarizer.heuristicSummary(
        sender: 'Tracker',
        message: 'Your tracking number is 483920, arriving today',
        isTamil: false,
      );
      expect(summary, contains('[REDACTED]'));
      expect(summary, isNot(contains('483920')));
    });
  });
}
