import 'package:erode_superapp/services/offline_sos_mesh_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SosBeaconPayload', () {
    test('encodes and parses beacon correctly', () {
      const payload = SosBeaconPayload(
        userId: 'user_test_123',
        latitude: 11.3410,
        longitude: 77.7172,
        timestamp: 1725510000000,
        batteryLevel: 85,
        userName: 'Test User',
      );

      final encoded = payload.encode();
      expect(encoded, startsWith('ALLIN1_SOS:user_test_123:11.341:77.7172:1725510000000:85'));

      final parsed = SosBeaconPayload.parse(encoded, rssi: -65);
      expect(parsed, isNotNull);
      expect(parsed!.userId, 'user_test_123');
      expect(parsed.latitude, closeTo(11.3410, 0.0001));
      expect(parsed.longitude, closeTo(77.7172, 0.0001));
      expect(parsed.timestamp, 1725510000000);
      expect(parsed.batteryLevel, 85);
      expect(parsed.rssi, -65);
      expect(parsed.estimatedDistanceMeters, isNotNull);
      expect(parsed.estimatedDistanceMeters, greaterThan(0));
    });

    test('returns null on invalid beacon string', () {
      expect(SosBeaconPayload.parse('INVALID_PACKET'), isNull);
      expect(SosBeaconPayload.parse('ALLIN1_SOS:short'), isNull);
    });

    test('estimateDistance calculates realistic RSSI distances', () {
      final closeDist = SosBeaconPayload.estimateDistance(-59); // at 1m
      expect(closeDist, closeTo(1.0, 0.1));

      final farDist = SosBeaconPayload.estimateDistance(-85); // far away
      expect(farDist, greaterThan(10.0));
    });

    test('Haversine distance and bearing calculation', () {
      // Erode Bus Stand to Railway Station (~2.5km)
      const lat1 = 11.3410;
      const lon1 = 77.7172;
      const lat2 = 11.3320;
      const lon2 = 77.7260;

      final dist = OfflineSosMeshService.calculateDistanceInMeters(lat1, lon1, lat2, lon2);
      expect(dist, greaterThan(1000));
      expect(dist, lessThan(3000));

      final bearing = OfflineSosMeshService.calculateBearing(lat1, lon1, lat2, lon2);
      expect(bearing, inInclusiveRange(0, 360));
    });
  });
}
