import 'package:flutter/material.dart';
import '../../services/chat_service.dart';

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final _service = ChatService();
  final _msgCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  String _department = 'operations';
  bool _sending = false;

  static const _departments = [
    ('operations', 'Operations', Icons.local_shipping_outlined),
    ('finance',    'Finance',    Icons.account_balance_outlined),
    ('hr',         'HR',         Icons.people_outline),
    ('support',    'Support',    Icons.support_agent_outlined),
  ];

  @override
  void dispose() {
    _msgCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _service.startConversation(
        department: _department,
        message: msg,
        subject: _subjectCtrl.text.trim().isEmpty ? null : _subjectCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Conversation'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          const Text('Department', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: _departments.map((d) {
            final selected = _department == d.$1;
            return ChoiceChip(
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(d.$3, size: 16, color: selected ? Colors.white : const Color(0xFF1565C0)),
                const SizedBox(width: 6),
                Text(d.$2),
              ]),
              selected: selected,
              selectedColor: const Color(0xFF1565C0),
              labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
              onSelected: (_) => setState(() => _department = d.$1),
            );
          }).toList()),

          const SizedBox(height: 20),
          const Text('Subject (optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectCtrl,
            decoration: InputDecoration(
              hintText: 'e.g. Salary query for June',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _msgCtrl,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Type your message...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send Message', style: TextStyle(fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }
}
