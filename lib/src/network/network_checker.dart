import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Utility class for checking internet connectivity and actual internet access.
///
/// It is cross-platform safe (Android, iOS, macOS, Web) and uses
/// a combination of interface checks and socket connections to verify
/// internet availability.
class NetworkChecker {
  /// Performs a one-time check to see if the device is connected to the internet.
  ///
  /// This check verifies both that a network interface is active and that
  /// data can actually flow (by attempting a socket connection).
  static Future<bool> isConnected() async {
    final results = await Connectivity().checkConnectivity();
    final hasInterface =
        results.any((result) => result != ConnectivityResult.none);

    if (!hasInterface) return false;

    // --- Platform Specific "Real" Internet Check ---

    if (kIsWeb) {
      // On Web, we can't use Sockets or InternetAddress.lookup.
      // Connectivity interface check is usually enough on modern browsers.
      return true;
    }

    try {
      // Using a raw Socket connection to a public DNS (8.8.8.8) is the most
      // reliable way to check for internet on mobile/desktop emulators.
      final socket = await Socket.connect('8.8.8.8', 53,
          timeout: const Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (_) {
      // Fallback: If 8.8.8.8 is blocked (e.g., some corporate networks),
      // try a simple hostname lookup.
      try {
        final result = await InternetAddress.lookup('pub.dev')
            .timeout(const Duration(seconds: 2));
        return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (__) {
        return false;
      }
    }
  }

  /// A stream that emits true/false whenever the network connectivity status changes.
  static Stream<bool> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged.map(
          (results) =>
              results.any((result) => result != ConnectivityResult.none),
        );
  }
}
