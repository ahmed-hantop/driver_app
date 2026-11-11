import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import 'chat_screen.dart';
import 'new_conversation_screen.dart';
import 'package:driver_app/main.dart' show chatRefreshNotifier;

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _service = ChatService();
  List<ChatConversation> _convs = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh list every 15 s and immediately when an FCM chat push arrives.
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadSilent());
    chatRefreshNotifier.addListener(_loadSilent);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    chatRefreshNotifier.removeListener(_loadSilent);
    super.dispose();
  }

  Future<void> _loadSilent() async {
    if (!mounted) return;
    try {
      final convs = await _service.fetchConversations();
      if (mounted) setState(() => _convs = convs);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final convs = await _service.fetchConversations();
      if (mounted) setState(() { _convs = convs; _loading = false; });
    } on ChatFeatureDisabledException {
      if (mounted) setState(() { _error = 'disabled'; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: _error != 'disabled'
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF1565C0),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewConversationScreen()),
              ).then((_) => _load()),
              child: const Icon(Icons.edit, color: Colors.white),
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error == 'disabled') {
      return _empty(Icons.chat_bubble_outline, 'Chat Unavailable',
          'The chat feature is currently disabled. Contact your manager.');
    }
    if (_error != null) {
      return _empty(Icons.error_outline, 'Failed to load', _error!,
          action: TextButton(onPressed: _load, child: const Text('Retry')));
    }
    if (_convs.isEmpty) {
      return _empty(Icons.forum_outlined, 'No conversations',
          'Tap the + button to start a new conversation with a department.');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _convs.length,
        separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) => _ConvTile(conv: _convs[i], onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversation: _convs[i])));
          _load();
        }),
      ),
    );
  }

  Widget _empty(IconData icon, String title, String subtitle, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 60, color: Colors.blue.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      ),
    );
  }
}

class _ConvTile extends StatelessWidget {
  final ChatConversation conv;
  final VoidCallback onTap;
  const _ConvTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasUnread = conv.unreadByDriver > 0;
    final statusColor = conv.status == 'resolved' ? Colors.green : conv.status == 'in_progress' ? Colors.blue : Colors.orange;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.12),
        child: Text(conv.departmentLabel[0].toUpperCase(),
            style: const TextStyle(color: Color(0xFF1565C0), fontWeight: FontWeight.bold)),
      ),
      title: Row(children: [
        Expanded(child: Text(conv.departmentLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Text(conv.status.replaceAll('_', ' '),
              style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
        ),
        if (conv.openTicketsCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.deepOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(
              '${conv.openTicketsCount} ticket${conv.openTicketsCount == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ]),
      subtitle: Text(
        conv.latestMessage?.body ?? (conv.subject ?? 'New conversation'),
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal),
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (conv.lastMessageAt != null)
          Text(_timeLabel(conv.lastMessageAt!), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        if (hasUnread)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFF1565C0), borderRadius: BorderRadius.circular(10)),
            child: Text('${conv.unreadByDriver}', style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
      ]),
      onTap: onTap,
    );
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}
