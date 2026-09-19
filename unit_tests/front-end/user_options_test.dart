import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/user.dart';

void main() {
  group('UserOptions.fromJson', () {
    test('Happy Scenario: parses valid JSON correctly', () {
      final json = {
        'id': 1,
        'user_id': 123,
        'theme': 'dark',
        'notifications_enabled': true,
        'email_notifications_enabled': true,
        'in_app_alerts_enabled': true,
        'language': 'en',
        'network_route_mode': 'tunnel',
        'api_base_home_url': 'http://192.168.1.10',
        'api_base_tunnel_url': 'http://100.81.199.36',
      };

      final options = UserOptions.fromJson(json);

      expect(options.id, 1);
      expect(options.userId, 123);
      expect(options.theme, 'dark');
      expect(options.notificationsEnabled, true);
      expect(options.emailNotificationsEnabled, true);
      expect(options.inAppAlertsEnabled, true);
      expect(options.language, 'en');
      expect(options.networkRouteMode, 'tunnel');
      expect(options.apiBaseHomeUrl, 'http://192.168.1.10');
      expect(options.apiBaseTunnelUrl, 'http://100.81.199.36');
    });

    test('Negative Scenario: handles missing keys with safe defaults', () {
      final json = {
        'id': 1,
        'user_id': 123,
        // missing all other keys
      };

      final options = UserOptions.fromJson(json);

      expect(options.theme, 'light'); // default
      expect(options.notificationsEnabled, true); // default (not false)
      expect(options.emailNotificationsEnabled, false); // default (not true)
      expect(options.language, 'en'); // default
      expect(options.networkRouteMode, 'home'); // default
    });

    test('Edge Case: handles type mismatches gracefully', () {
      final json = {
        'id': "1", // String instead of int
        'user_id': 123.5, // Double instead of int
        'theme': 123, // Int instead of String
        'notifications_enabled': "true", // String instead of bool
      };

      final options = UserOptions.fromJson(json);

      // id is 0 because "1" is not num
      expect(options.id, 0);
      // user_id is 123 because 123.5 is num and toInt() is 123
      expect(options.userId, 123);
      // theme is "123" because of .toString()
      expect(options.theme, "123");
      // notifications_enabled is true because "true" != false
      expect(options.notificationsEnabled, true);
    });
  });
}
