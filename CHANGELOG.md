## 1.0.0

### 🎉 Initial Release — Syncraft

A robust offline-first API request queuing package for Flutter.

### ✨ Features
- Offline-first architecture for seamless app experience without internet
- Automatic background sync when connectivity is restored
- Persistent request storage using SQLite (survives app restarts & crashes)
- Built-in retry mechanism for failed API requests
- Lightweight and easy integration using `http` and `sqflite`

### 🚀 Core Functionality
- Intercepts API requests and queues them when offline
- Automatically processes queued requests when network is available
- Supports manual retry for failed requests
- Provides APIs to fetch pending and failed queue items

### 📦 Included
- `SyncService` for managing request queue and sync lifecycle
- Local database handling for storing API requests
- Network listener using `connectivity_plus`

### 🔧 Platform Support
- Android (requires INTERNET & ACCESS_NETWORK_STATE permissions)
- iOS (no additional setup required)

### 📚 Documentation
- Detailed setup and usage instructions included in README
- Example project available in `/example` directory

### 🛠️ Notes
- Ensure `SyncService.init()` is called before using the package
- Designed for REST API workflows with JSON payloads