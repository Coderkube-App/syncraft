# Syncraft

A robust offline-first API request queuing package for Flutter. Syncraft automatically intercepts your API requests when the device is offline, saves them securely to a local SQLite database, and automatically syncs them to your server the moment an internet connection is restored.

## Features

- **Offline-First Architecture**: Your app continues to work seamlessly even without an internet connection.
- **Automatic Background Sync**: Automatically detects when network connectivity is restored and syncs pending requests.
- **Persistent Storage**: Safely stores API requests in a local SQLite database so they survive app restarts and crashes.
- **Retry Mechanism**: Automatically queues failed requests and allows for manual or automatic retries.
- **Plug-and-Play**: Built with `http` and `sqflite`, making it lightweight and easy to integrate into any project.

## Getting started

Add `syncraft` to your `pubspec.yaml`:

```yaml
dependencies:
  syncraft: ^1.0.1
```

### Android Requirements
Make sure you have the following permissions in your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

## Usage

### 1. Initialization
Call `init()` on `SyncService` when your application starts (for example, in your `main` function or the initial screen's `initState`).

```dart
import 'package:flutter/material.dart';
import 'package:syncraft/syncraft.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final syncService = SyncService();
  await syncService.init(); // Starts listening to network changes
  
  runApp(MyApp());
}
```

### 2. Sending Data
Whenever you need to send an API request (e.g., submitting a form, liking a post), use `SyncService.sendData()`. Syncraft will automatically handle queuing it if the user is offline.

```dart
final syncService = SyncService();

await syncService.sendData(
  endpoint: 'https://api.example.com/v1/posts',
  method: 'POST',
  data: {
    'title': 'My awesome post',
    'body': 'This was drafted offline!',
  },
);
```

### 3. Managing the Queue
You can fetch pending or failed items, which is useful for displaying a badge count in your UI or allowing users to manually trigger a retry for failed items.

```dart
// Get the number of pending sync items
final pendingItems = await syncService.getPendingItems();
print('Pending: ${pendingItems.length}');

// Manually retry any failed requests (e.g. server 500 errors)
await syncService.retryFailed();
```

## How it works

1. `sendData` creates a `SyncItem` with a unique ID and saves it to a local SQLite database.
2. If the device is online, it attempts to send the request immediately.
3. If the device is offline, it skips sending. The request remains safely in the local database.
4. When `connectivity_plus` detects that the network is restored, Syncraft automatically fires background workers to sync pending and failed items.
5. Successfully synced items are removed from the database.

## Additional information

For more detailed examples, check out the `/example` folder in the repository.
