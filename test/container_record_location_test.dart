import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/container_service.dart';

void main() {
  test('legacy and nested coordinates identify the recorded location', () {
    for (final record in [
      {'latitude': '31.4', 'longitude': '34.3'},
      {'gpsCoordinates': {'lat': 31.4, 'lng': 34.3}},
    ]) {
      final item = ContainerItem.fromMap(record);
      expect(item.latitude, 31.4);
      expect(item.longitude, 34.3);
      expect(item.status, isEmpty);
    }
  });

  test('an incomplete or invalid pair never points to a substitute location', () {
    for (final record in [
      {'latitude': 31.4},
      {'latitude': 91, 'longitude': 34.3},
      {'latitude': 'NaN', 'longitude': 34.3},
    ]) {
      final item = ContainerItem.fromMap(record);
      expect([item.latitude, item.longitude], [0, 0]);
    }
  });
}
