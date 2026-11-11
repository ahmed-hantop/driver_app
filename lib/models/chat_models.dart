class ChatMessage {
  final int id;
  final int conversationId;
  final String senderType; // 'driver' or 'admin'
  final int senderId;
  final String? body;
  final String? attachmentUrl;
  final String? attachmentType;
  final String status; // sent, delivered, read
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.senderId,
    this.body,
    this.attachmentUrl,
    this.attachmentType,
    required this.status,
    required this.createdAt,
  });

  bool get isFromDriver => senderType == 'driver';

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id:             (j['id'] as num).toInt(),
      conversationId: (j['conversation_id'] as num).toInt(),
      senderType:     (j['sender_type'] ?? 'driver').toString(),
      senderId:       (j['sender_id'] as num? ?? 0).toInt(),
      body:           j['body']?.toString(),
      attachmentUrl:  j['attachment_url']?.toString(),
      attachmentType: j['attachment_type']?.toString(),
      status:         (j['status'] ?? 'sent').toString(),
      createdAt:      DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class ChatConversation {
  final int id;
  final int driverId;
  final String department;
  final String? subject;
  final String status;
  final bool driverBlocked;
  final int unreadByDriver;
  final int openTicketsCount;
  final DateTime? lastMessageAt;
  final ChatMessage? latestMessage;

  ChatConversation({
    required this.id,
    required this.driverId,
    required this.department,
    this.subject,
    required this.status,
    required this.driverBlocked,
    required this.unreadByDriver,
    required this.openTicketsCount,
    this.lastMessageAt,
    this.latestMessage,
  });

  String get departmentLabel {
    const map = {'operations': 'Operations', 'finance': 'Finance', 'hr': 'HR', 'support': 'Support'};
    return map[department] ?? department;
  }

  factory ChatConversation.fromJson(Map<String, dynamic> j) {
    final latest = j['latest_message'];
    ChatMessage? latestMsg;
    if (latest is List && latest.isNotEmpty) {
      latestMsg = ChatMessage.fromJson(latest.first as Map<String, dynamic>);
    } else if (latest is Map<String, dynamic>) {
      latestMsg = ChatMessage.fromJson(latest);
    }

    return ChatConversation(
      id:             (j['id'] as num).toInt(),
      driverId:       (j['driver_id'] as num).toInt(),
      department:     (j['department'] ?? 'operations').toString(),
      subject:        j['subject']?.toString(),
      status:         (j['status'] ?? 'open').toString(),
      driverBlocked:  j['driver_blocked'] == true || j['driver_blocked'] == 1,
      unreadByDriver: (j['unread_by_driver'] as num? ?? 0).toInt(),
      openTicketsCount: (j['open_tickets_count'] as num? ?? 0).toInt(),
      lastMessageAt:  DateTime.tryParse(j['last_message_at']?.toString() ?? ''),
      latestMessage:  latestMsg,
    );
  }
}

class ChatTicketUpdate {
  final int id;
  final String action;
  final String? body;
  final String userName;
  final DateTime createdAt;

  ChatTicketUpdate({
    required this.id,
    required this.action,
    this.body,
    required this.userName,
    required this.createdAt,
  });

  factory ChatTicketUpdate.fromJson(Map<String, dynamic> j) {
    final user = j['user'];
    return ChatTicketUpdate(
      id: (j['id'] as num).toInt(),
      action: (j['action'] ?? 'updated').toString(),
      body: j['body']?.toString(),
      userName: user is Map<String, dynamic> ? (user['name'] ?? 'System').toString() : 'System',
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class ChatTicket {
  final int id;
  final String subject;
  final String description;
  final String priority;
  final String status;
  final String? resolutionNotes;
  final String createdByName;
  final String? assignedToName;
  final DateTime? openedAt;
  final DateTime? resolvedAt;
  final List<ChatTicketUpdate> updates;

  ChatTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    this.resolutionNotes,
    required this.createdByName,
    this.assignedToName,
    this.openedAt,
    this.resolvedAt,
    required this.updates,
  });

  bool get isActive => const {'open', 'in_progress', 'waiting'}.contains(status);

  factory ChatTicket.fromJson(Map<String, dynamic> j) {
    final createdBy = j['created_by'];
    final assignedTo = j['assigned_to'];
    final updatesRaw = j['updates'] as List? ?? const [];

    return ChatTicket(
      id: (j['id'] as num).toInt(),
      subject: (j['subject'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      priority: (j['priority'] ?? 'medium').toString(),
      status: (j['status'] ?? 'open').toString(),
      resolutionNotes: j['resolution_notes']?.toString(),
      createdByName: createdBy is Map<String, dynamic> ? (createdBy['name'] ?? 'DMS').toString() : 'DMS',
      assignedToName: assignedTo is Map<String, dynamic> ? assignedTo['name']?.toString() : null,
      openedAt: DateTime.tryParse(j['opened_at']?.toString() ?? ''),
      resolvedAt: DateTime.tryParse(j['resolved_at']?.toString() ?? ''),
      updates: updatesRaw.map((e) => ChatTicketUpdate.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class AppFeatures {
  final bool payrollEnabled;
  final bool chatEnabled;
  final bool callsEnabled;

  const AppFeatures({
    this.payrollEnabled = true,
    this.chatEnabled = true,
    this.callsEnabled = true,
  });

  factory AppFeatures.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AppFeatures();
    bool b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
    return AppFeatures(
      payrollEnabled: b(j['payroll_enabled']),
      chatEnabled:    b(j['chat_enabled']),
      callsEnabled:   b(j['calls_enabled']),
    );
  }

  static const AppFeatures defaults = AppFeatures();
}

class IncomingCallData {
  final int callLogId;
  final String livekitUrl;
  final String room;
  final String token;
  final String callType; // voice, video
  final String callerName;

  IncomingCallData({
    required this.callLogId,
    required this.livekitUrl,
    required this.room,
    required this.token,
    required this.callType,
    required this.callerName,
  });

  factory IncomingCallData.fromJson(Map<String, dynamic> j) {
    return IncomingCallData(
      callLogId:  (j['call_log_id'] as num).toInt(),
      livekitUrl: (j['livekit_url'] ?? '').toString(),
      room:       (j['room'] ?? '').toString(),
      token:      (j['token'] ?? '').toString(),
      callType:   (j['call_type'] ?? 'voice').toString(),
      callerName: (j['caller_name'] ?? 'Admin').toString(),
    );
  }
}
