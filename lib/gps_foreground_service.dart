import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

@pragma('vm:entry-point')
void gpsServiceMain(ServiceInstance service) {
  service.on('startTracking').listen((event) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Firebase already initialized
    }

    final prefs = await SharedPreferences.getInstance();
    String? idToken = prefs.getString('shift_idToken');
    String? refreshToken = prefs.getString('shift_refreshToken');
    final String? shiftIdFromEvent = event?['shiftId'] as String?;
    if (shiftIdFromEvent != null) {
      await prefs.setString('shift_shiftId', shiftIdFromEvent);
    }
    String? shiftId = shiftIdFromEvent ?? prefs.getString('shift_shiftId');

    Timer? tokenRefreshTimer;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      tokenRefreshTimer = Timer.periodic(const Duration(minutes: 55), (_) async {
        try {
          final newToken = await _refreshIdToken(refreshToken);
          if (newToken != null) {
            idToken = newToken;
            final prefs2 = await SharedPreferences.getInstance();
            await prefs2.setString('shift_idToken', newToken);
          }
        } catch (e) {
          // ignore
        }
      });
    }

    StreamSubscription<Position>? posStream;
    posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) async {
      final token = idToken;
      if (token == null || token.isEmpty || shiftId == null) return;
      try {
        await http.post(
          Uri.parse(
            'https://us-central1-tooltrack-f5a6a.cloudfunctions.net/updateGpsLocation',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token,
          },
          body: jsonEncode({
            'shiftId': shiftId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'timestamp': position.timestamp.toIso8601String(),
          }),
        );
      } catch (e) {
        // ignore
      }
    });

    service.on('stopTracking').listen((_) async {
      tokenRefreshTimer?.cancel();
      await posStream?.cancel();
      await service.stopSelf();
    });
  });
}

Future<String?> _refreshIdToken(String refreshToken) async {
  const apiKey = 'AIzaSyBWM0gMgkuMr5eAtbET1OtQn08Ld3_7cnI';
  final response = await http.post(
    Uri.parse(
      'https://securetoken.googleapis.com/v1/token?key=' + apiKey,
    ),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: 'grant_type=refresh_token&refresh_token=' + refreshToken,
  );
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data['id_token'] as String?;
  }
  return null;
}
