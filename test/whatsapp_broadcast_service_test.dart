import 'package:erode_superapp/services/whatsapp/whatsapp_broadcast_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WhatsAppBroadcastService Tests', () {
    test('formats 10-digit, 11-digit and +91 phone numbers correctly', () {
      expect(WhatsAppBroadcastService.formatPhoneNumber('9876543210'), '919876543210');
      expect(WhatsAppBroadcastService.formatPhoneNumber('09876543210'), '919876543210');
      expect(WhatsAppBroadcastService.formatPhoneNumber('+91 98765 43210'), '919876543210');
      expect(WhatsAppBroadcastService.formatPhoneNumber('919876543210'), '919876543210');
    });

    test('parses multi-format raw recipient numbers list', () {
      const raw = '''
9876543210
Karthik: 9842112233
09597879191
9876543210, +91 91234 56789; Ramesh - 9443322110
''';
      final recipients = WhatsAppBroadcastService.parseNumbers(raw);

      // Unique phone numbers deduplicated
      expect(recipients.length, 5);
      expect(recipients[0].phoneNumber, '919876543210');
      expect(recipients[1].name, 'Karthik');
      expect(recipients[1].phoneNumber, '919842112233');
      expect(recipients[2].phoneNumber, '919597879191');
      expect(recipients[3].phoneNumber, '919123456789');
      expect(recipients[4].name, 'Ramesh');
      expect(recipients[4].phoneNumber, '919443322110');
    });

    test('builds WhatsApp API URL with message and optional video link', () {
      final url = WhatsAppBroadcastService.buildWhatsAppUrl(
        phoneNumber: '9876543210',
        message: 'Hi from NJ Tech!',
        videoUrl: 'https://res.cloudinary.com/njtech/video.mp4',
      );

      expect(url.startsWith('https://api.whatsapp.com/send?phone=919876543210&text='), true);
      expect(url.contains('Hi%20from%20NJ%20Tech!'), true);
      expect(url.contains('Watch%20Video%3A%20https%3A%2F%2Fres.cloudinary.com%2Fnjtech%2Fvideo.mp4'), true);
    });
  });
}
