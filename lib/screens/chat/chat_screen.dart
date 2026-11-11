import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../models/chat_models.dart';
import '../../services/chat_service.dart';
import 'package:driver_app/main.dart' show chatRefreshNotifier;

class ChatScreen extends StatefulWidget {
  final ChatConversation conversation;
  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _service       = ChatService();
  final _msgCtrl       = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final _audioRecorder = Record();

  List<ChatMessage> _messages = [];
  List<ChatTicket> _tickets = [];
  bool _loading  = true;
  bool _ticketsLoading = true;
  bool _sending  = false;
  bool _recording = false;
  bool _showScrollDown = false;
  String _selectedView = 'messages';
  String? _recordingPath;
  int _recSeconds = 0;
  Timer? _recTimer;
  Timer? _pollTimer;
  Timer? _typingTimer;
  DateTime? _lastTypingSent;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadSilent());
    chatRefreshNotifier.addListener(_loadSilent);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    chatRefreshNotifier.removeListener(_loadSilent);
    _pollTimer?.cancel();
    _typingTimer?.cancel();
    _recTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onScroll() {
    final atBottom = _isAtBottom;
    if (atBottom != !_showScrollDown) {
      setState(() => _showScrollDown = !atBottom);
    }
  }

  Future<void> _load() async {
    try {
      final msgs = await _service.fetchMessages(widget.conversation.id);
      final tickets = await _service.fetchTickets(widget.conversation.id);
      if (mounted) {
        setState(() {
          _messages = msgs.reversed.toList();
          _tickets = tickets;
          _loading = false;
          _ticketsLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _ticketsLoading = false; });
    }
  }

  Future<void> _loadSilent() async {
    if (!mounted) return;
    try {
      final msgs = await _service.fetchMessages(widget.conversation.id);
      final tickets = await _service.fetchTickets(widget.conversation.id);
      if (mounted) {
        final wasAtBottom = _isAtBottom;
        setState(() {
          _messages = msgs.reversed.toList();
          _tickets = tickets;
          _ticketsLoading = false;
        });
        if (wasAtBottom) _scrollToBottom();
      }
    } catch (_) {}
  }

  bool get _isAtBottom {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 60;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTyping() {
    final now = DateTime.now();
    if (_lastTypingSent == null || now.difference(_lastTypingSent!) > const Duration(seconds: 3)) {
      _lastTypingSent = now;
      _service.sendTypingIndicator(widget.conversation.id);
    }
  }

  Future<void> _send({File? attachment}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && attachment == null) return;
    setState(() => _sending = true);
    try {
      await _service.sendMessage(widget.conversation.id, text, attachment: attachment);
      _msgCtrl.clear();
      await _loadSilent();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) _send(attachment: File(picked.path));
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      path: _recordingPath!,
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      samplingRate: 44100,
    );
    if (mounted) {
      setState(() { _recording = true; _recSeconds = 0; });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recSeconds++);
      });
    }
  }

  Future<void> _stopAndSend() async {
    _recTimer?.cancel();
    final path = await _audioRecorder.stop();
    if (mounted) setState(() { _recording = false; _recSeconds = 0; });
    if (path != null && mounted) {
      await _send(attachment: File(path));
    }
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    await _audioRecorder.stop();
    if (_recordingPath != null) {
      try { await File(_recordingPath!).delete(); } catch (_) {}
    }
    if (mounted) setState(() { _recording = false; _recSeconds = 0; });
  }

  String get _recTimeLabel {
    final m = (_recSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isResolved = widget.conversation.status == 'resolved';
    final isBlocked  = widget.conversation.driverBlocked;

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.conversation.departmentLabel),
          Text(widget.conversation.subject ?? '',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
        ]),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: Stack(children: [
        Column(children: [
          if (isResolved) _banner(Colors.green, Icons.check_circle_outline, 'Conversation resolved'),
          if (isBlocked)  _banner(Colors.red,   Icons.block,                'Your chat access is restricted'),

          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: const Color(0xFFF7F9FB),
            child: Row(children: [
              Expanded(child: _viewSwitch('messages', 'Messages', Icons.chat_bubble_outline)),
              const SizedBox(width: 8),
              Expanded(child: _viewSwitch('tickets', 'Tickets', Icons.confirmation_number_outlined,
                  trailingText: _tickets.where((t) => t.isActive).length.toString())),
            ]),
          ),

          Expanded(child: _selectedView == 'messages' ? _buildMessagesPane() : _buildTicketsPane()),

          if (_selectedView == 'messages' && !isResolved && !isBlocked)
            _recording ? _recordingBar() : _inputBar(),
        ]),

        // Scroll-to-bottom button
        if (_selectedView == 'messages' && _showScrollDown)
          Positioned(
            right: 12,
            bottom: (!isResolved && !isBlocked) ? 74 : 12,
            child: GestureDetector(
              onTap: _scrollToBottom,
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF075E54),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildMessagesPane() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _itemCount,
      itemBuilder: _buildItem,
    );
  }

  Widget _buildTicketsPane() {
    if (_ticketsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.confirmation_number_outlined, size: 56, color: Colors.blueGrey.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No tickets yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'If the DMS team opens a support ticket for this chat, it will appear here with its progress and resolution.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSilent,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _tickets.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _TicketCard(ticket: _tickets[index]),
      ),
    );
  }

  Widget _viewSwitch(String value, String label, IconData icon, {String? trailingText}) {
    final selected = _selectedView == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedView = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? const Color(0xFF1565C0) : const Color(0xFFD9E2EC)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: selected ? Colors.white : const Color(0xFF52606D)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFF334E68), fontWeight: FontWeight.w700)),
          if (trailingText != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.18) : const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                trailingText,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF1565C0),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // Build a flat list of date-separator + message items
  int get _itemCount {
    int count = 0;
    DateTime? lastDate;
    for (final msg in _messages) {
      final msgDate = DateTime(msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);
      if (lastDate == null || msgDate != lastDate) { count++; lastDate = msgDate; }
      count++;
    }
    return count;
  }

  Widget _buildItem(BuildContext context, int index) {
    int flat = 0;
    DateTime? lastDate;
    for (final msg in _messages) {
      final msgDate = DateTime(msg.createdAt.year, msg.createdAt.month, msg.createdAt.day);
      bool needsSep = lastDate == null || msgDate != lastDate;
      if (needsSep) {
        if (flat == index) return _DateSeparator(date: msgDate);
        flat++;
        lastDate = msgDate;
      }
      if (flat == index) return _MessageBubble(msg: msg);
      flat++;
    }
    return const SizedBox.shrink();
  }

  Widget _banner(Color color, IconData icon, String text) {
    return Container(
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontSize: 13)),
      ]),
    );
  }

  Widget _recordingBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.red[50],
        child: Row(children: [
          const Icon(Icons.mic, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            'Recording $_recTimeLabel',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _cancelRecording,
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _stopAndSend,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Color(0xFF075E54), shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        color: const Color(0xFFF0F2F5),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.image_outlined, color: Color(0xFF54656F)),
            onPressed: _pickImage,
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _msgCtrl,
                maxLines: null,
                onChanged: (_) {
                  _onTyping();
                  setState(() {});
                },
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _sending
              ? const SizedBox(width: 44, height: 44,
                  child: Padding(padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF075E54))))
              : GestureDetector(
                  onTap: _msgCtrl.text.trim().isNotEmpty ? () => _send() : null,
                  onLongPressStart: _msgCtrl.text.trim().isEmpty ? (_) => _startRecording() : null,
                  onLongPressEnd:   _msgCtrl.text.trim().isEmpty ? (_) => _stopAndSend() : null,
                  child: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: Color(0xFF075E54), shape: BoxShape.circle),
                    child: Icon(
                      _msgCtrl.text.trim().isNotEmpty ? Icons.send : Icons.mic,
                      color: Colors.white, size: 20,
                    ),
                  ),
                ),
        ]),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final ChatTicket ticket;
  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (ticket.status) {
      'resolved' => Colors.green,
      'closed' => Colors.blueGrey,
      'waiting' => Colors.orange,
      'in_progress' => const Color(0xFF1565C0),
      _ => Colors.deepPurple,
    };
    final priorityColor = switch (ticket.priority) {
      'urgent' => Colors.red,
      'high' => Colors.deepOrange,
      'medium' => Colors.amber.shade800,
      _ => Colors.blueGrey,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('#${ticket.id} ${ticket.subject}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            _badge(ticket.status.replaceAll('_', ' '), statusColor.withValues(alpha: 0.12), statusColor),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _badge(ticket.priority, priorityColor.withValues(alpha: 0.12), priorityColor),
            if (ticket.assignedToName != null) _badge('Assigned to ${ticket.assignedToName}', const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
            _badge('Opened by ${ticket.createdByName}', const Color(0xFFF0F4F8), const Color(0xFF52606D)),
          ]),
          const SizedBox(height: 12),
          Text(ticket.description, style: const TextStyle(height: 1.4, color: Color(0xFF334E68))),
          if (ticket.resolutionNotes != null && ticket.resolutionNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF0FFF4), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Resolution', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                const SizedBox(height: 6),
                Text(ticket.resolutionNotes!, style: const TextStyle(color: Color(0xFF166534))),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          const Text('Activity', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF52606D))),
          const SizedBox(height: 8),
          ...ticket.updates.take(5).map((update) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${update.userName} • ${update.action.replaceAll('_', ' ')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        if (update.body != null && update.body!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(update.body!, style: const TextStyle(color: Color(0xFF334E68))),
                        ],
                      ]),
                    ),
                  ),
                ]),
              )),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date separator
// ---------------------------------------------------------------------------

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final label = date == today
        ? 'Today'
        : date == yesterday
            ? 'Yesterday'
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD9DBD5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF54656F))),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isMe = msg.isFromDriver;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFD9FDD3) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(8),
            topRight:    const Radius.circular(8),
            bottomLeft:  Radius.circular(isMe ? 8 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 8),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Admin',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF00A884), fontWeight: FontWeight.w600)),
              ),

            if (msg.body != null && msg.body!.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(msg.body!,
                    style: const TextStyle(color: Color(0xFF111B21), fontSize: 14.5, height: 1.4)),
              ),

            if (msg.attachmentType == 'image' && msg.attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    msg.attachmentUrl!,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 200, height: 120,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : SizedBox(
                            width: 200, height: 120,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2, color: const Color(0xFF00A884),
                              ),
                            ),
                          ),
                  ),
                ),
              ),

            if (msg.attachmentType == 'audio' && msg.attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _AudioPlayer(url: msg.attachmentUrl!),
              ),

            if (msg.attachmentType == 'file' && msg.attachmentUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.attach_file, size: 14, color: Color(0xFF667781)),
                  const SizedBox(width: 4),
                  Text('Attachment',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF667781),
                          decoration: TextDecoration.underline)),
                ]),
              ),

            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _timeLabel(msg.createdAt),
                style: const TextStyle(fontSize: 10, color: Color(0xFF667781)),
              ),
              if (isMe) ...[
                const SizedBox(width: 3),
                Icon(
                  msg.status == 'read' || msg.status == 'delivered' ? Icons.done_all : Icons.done,
                  size: 14,
                  color: msg.status == 'read' ? const Color(0xFF53BDEB) : const Color(0xFF8696A0),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final h = dt.hour > 12 ? (dt.hour - 12).toString() : (dt.hour == 0 ? '12' : dt.hour.toString());
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

// ---------------------------------------------------------------------------
// Audio player widget
// ---------------------------------------------------------------------------

class _AudioPlayer extends StatefulWidget {
  final String url;
  const _AudioPlayer({required this.url});

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  final _player = AudioPlayer();
  bool _playing  = false;
  Duration _pos  = Duration.zero;
  Duration _dur  = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _pos = Duration.zero; });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total  = _dur.inSeconds > 0 ? _dur.inSeconds.toDouble() : 1.0;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: _toggle,
        child: Container(
          width: 36, height: 36,
          decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
          child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
        ),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 120,
          height: 20,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: const Color(0xFF00A884),
              inactiveTrackColor: Colors.grey[300]!,
              thumbColor: const Color(0xFF00A884),
            ),
            child: Slider(
              value: _pos.inSeconds.toDouble().clamp(0, total),
              max: total,
              onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
            ),
          ),
        ),
        Text(
          _playing ? _fmt(_pos) : _fmt(_dur),
          style: const TextStyle(fontSize: 9, color: Color(0xFF667781)),
        ),
      ]),
    ]);
  }
}
