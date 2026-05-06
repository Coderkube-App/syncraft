import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:syncraft/syncraft.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syncraft Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SyncraftDemoPage(),
    );
  }
}

class SyncraftDemoPage extends StatefulWidget {
  const SyncraftDemoPage({super.key});

  @override
  State<SyncraftDemoPage> createState() => _SyncraftDemoPageState();
}

class _SyncraftDemoPageState extends State<SyncraftDemoPage> {
  // ─── SyncService setup with custom config and callbacks ───────────────────
  late final SyncService _sync;

  bool _isOnline = true;
  int _pendingCount = 0;
  List<Map<String, dynamic>> _posts = [];
  String _postStatus = ''; // status message from GET scenario
  bool _fromCache = false;
  bool _hasNoCache = false;

  // Form controllers for the POST scenario
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Build SyncService with fully custom messages
    _sync = SyncService(
      config: const SyncCraftConfig(
        msgQueued: 'Form saved offline. Will submit automatically.',
        msgSynced: 'Form submitted in the background!',
        msgFailed: 'Submit failed. Stored safely — will retry.',
        msgNoCache: 'Connect once to load data. Will appear automatically.',
        msgCachedBanner: 'Showing saved data. Live data coming soon.',
        msgNetworkRestored: 'Back online! Syncing your data...',
        timeoutSeconds: 30,
        autoSyncOnReconnect: true,
        cacheDurationHours: 24,
        maxCacheRows: 200,
        maxCacheSizeMB: 10,
      ),
      // onQueued: message comes from SyncCraftConfig.msgQueued
      onQueued: (item, message) => _showSnackbar(message, isSuccess: false),
      // onSynced: message comes from SyncCraftConfig.msgSynced
      onSynced: (item, message) {
        _showSnackbar(message, isSuccess: true);
        _refreshPendingCount();
      },
      // onFailed: message comes from SyncCraftConfig.msgFailed
      onFailed: (item, error, message) => _showSnackbar(message, isError: true),
    );

    _initService();
  }

  Future<void> _initService() async {
    // Init must be called once before getData/sendData
    await _sync.init();

    // Check initial network state
    final online = await NetworkChecker.isConnected();
    if (mounted) setState(() => _isOnline = online);

    // Listen to connectivity changes for live UI badge
    NetworkChecker.onConnectivityChanged.listen((isOnline) {
      if (mounted) {
        setState(() => _isOnline = isOnline);
        if (isOnline)
          Future.delayed(const Duration(seconds: 3), _refreshPendingCount);
      }
    });

    // Listen to statusStream for live pending badge
    _sync.statusStream.listen((_) => _refreshPendingCount());

    await _refreshPendingCount();
  }

  // ─── Scenario 1: GET Posts ─────────────────────────────────────────────────
  Future<void> _loadPosts() async {
    final result = await _sync.getData(
      endpoint: 'https://jsonplaceholder.typicode.com/posts?_limit=5',
    );

    if (!mounted) return;

    if (result.success && result.data != null) {
      // Online or cached — show the data
      final List<dynamic> raw = jsonDecode(result.data!);
      setState(() {
        _posts = raw.cast<Map<String, dynamic>>();
        _fromCache = result.fromCache;
        _hasNoCache = false;
        _postStatus = result.message; // '' if live, cached msg if offline
      });
    } else if (result.hasNoCache) {
      // First time offline — no data yet
      setState(() {
        _posts = [];
        _hasNoCache = true;
        _postStatus = result.message; // config.msgNoCache
      });
    } else if (result.queued) {
      setState(() {
        _posts = [];
        _hasNoCache = true;
        _postStatus = result.message;
      });
    }

    await _refreshPendingCount();
  }

  // ─── Scenario 2: POST Form ─────────────────────────────────────────────────
  Future<void> _submitForm() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      _showSnackbar('Please fill in Name and Email', isError: true);
      return;
    }

    final result = await _sync.sendData(
      endpoint: 'https://jsonplaceholder.typicode.com/posts',
      method: 'POST',
      data: {'name': name, 'email': email, 'userId': 1},
    );

    if (!mounted) return;

    if (result.queued && !result.success) {
      // Already handled by onQueued callback
    } else if (result.queued) {
      // onQueued callback fired — snackbar already shown
    } else if (result.success) {
      _showSnackbar('Form submitted!', isSuccess: true);
      _nameController.clear();
      _emailController.clear();
    }

    await _refreshPendingCount();
  }

  // ─── Retry Failed ──────────────────────────────────────────────────────────
  Future<void> _retryFailed() async {
    await _sync.retryFailed();
    await Future.delayed(const Duration(seconds: 2));
    await _refreshPendingCount();
  }

  // ─── Refresh pending badge count ───────────────────────────────────────────
  Future<void> _refreshPendingCount() async {
    final pending = await _sync.getPendingItems();
    if (mounted) setState(() => _pendingCount = pending.length);
  }

  // ─── Snackbar helper ───────────────────────────────────────────────────────
  void _showSnackbar(
    String msg, {
    bool isSuccess = false,
    bool isError = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.shade700
            : isSuccess
            ? Colors.green.shade700
            : Colors.blueGrey.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _sync.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ─── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncraft Demo'),
        actions: [
          // Scenario 3: Pending badge — live count from statusStream
          if (_pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  'Pending: $_pendingCount',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: Colors.orange.shade800,
              ),
            ),
          const SizedBox(width: 8),
        ],
        // Connectivity bar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            color: _isOnline ? Colors.green.shade700 : Colors.red.shade700,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            child: Text(
              _isOnline ? '🟢  Online' : '🔴  Offline — requests will queue',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Scenario 1: GET Posts ────────────────────────────────────
            _SectionHeader(
              icon: Icons.cloud_download_outlined,
              title: 'Scenario 1 — GET Request',
              subtitle: 'Returns cache instantly if offline. Never freezes.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loadPosts,
                icon: const Icon(Icons.refresh),
                label: const Text('Load Posts'),
              ),
            ),
            if (_fromCache && _postStatus.isNotEmpty)
              _InfoBanner(message: _postStatus, color: Colors.amber.shade900),
            if (_hasNoCache && _postStatus.isNotEmpty)
              _InfoBanner(
                message: _postStatus,
                color: Colors.blueGrey.shade700,
              ),
            const SizedBox(height: 8),
            if (_posts.isEmpty && !_hasNoCache)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Tap "Load Posts" above',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            if (_hasNoCache) _EmptyStateCard(message: _postStatus),
            ..._posts.map(
              (post) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text('${post['id']}')),
                  title: Text(
                    post['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    post['body'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            const Divider(height: 32),

            // ── Scenario 2: POST Form ────────────────────────────────────
            _SectionHeader(
              icon: Icons.send_outlined,
              title: 'Scenario 2 — POST Request',
              subtitle: 'Queues silently if offline. Syncs automatically.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitForm,
                    icon: const Icon(Icons.send),
                    label: const Text('Submit'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _retryFailed,
                  icon: const Icon(Icons.replay),
                  label: const Text('Retry Failed'),
                ),
              ],
            ),

            const Divider(height: 32),

            // ── Scenario 3: Sync Badge info ──────────────────────────────
            _SectionHeader(
              icon: Icons.sync,
              title: 'Scenario 3 — Live Sync Badge',
              subtitle: 'Pending count in AppBar updates automatically.',
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending in queue: $_pendingCount',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Turn off WiFi, submit the form, '
                      'then turn WiFi back on to see auto-sync.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable UI widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  final Color color;

  const _InfoBanner({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final String message;

  const _EmptyStateCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
