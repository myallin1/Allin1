import 'package:erode_superapp/services/admin_alert_notification_service.dart';
import 'package:erode_superapp/services/admin_live_alert_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminAlertNotificationService (contract: never throws)', () {
    test('cancelAlert completes safely with payload ID', () async {
      await expectLater(
        AdminAlertNotificationService.cancelAlert('call_12345'),
        completes,
      );
    });

    test('showIncomingCallAlert completes without throwing', () async {
      await expectLater(
        AdminAlertNotificationService.showIncomingCallAlert(
          callId: 'call_test_999',
          callerName: 'Ramesh',
          callerPhone: '9876543210',
        ),
        completes,
      );
    });

    test('showForegroundAlert completes without throwing', () async {
      await expectLater(
        AdminAlertNotificationService.showForegroundAlert(
          title: '🚕 New Bike Booking',
          body: 'Erode → Perundurai',
          payloadId: 'ride_123',
        ),
        completes,
      );
    });

    test('handleNotificationResponse safely handles empty or unknown payload', () async {
      const response = NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
      );
      await expectLater(
        AdminAlertNotificationService.handleNotificationResponse(response),
        completes,
      );
    });

    test('handleNotificationResponse safely handles admin_incoming_call payload', () async {
      const response = NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: '{"type":"admin_incoming_call","callId":"call_abc"}',
      );
      await expectLater(
        AdminAlertNotificationService.handleNotificationResponse(response),
        completes,
      );
    });
  });

  group('AdminLiveAlertService lifecycle', () {
    test('stop is safe and repeatable when idle', () {
      expect(AdminLiveAlertService.instance.stop, returnsNormally);
      expect(AdminLiveAlertService.instance.stop, returnsNormally);
    });
  });
}
