// This file checks internet connectivity using connectivity_plus
// and performs a real internet access check.
// It is cross-platform safe (Android, iOS, macOS, Web).

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkChecker {
  // One-time check — are we connected AND have internet access?
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

  // Stream that emits true/false every time connectivity changes.
  static Stream<bool> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged.map(
          (results) =>
              results.any((result) => result != ConnectivityResult.none),
        );
  }
}
