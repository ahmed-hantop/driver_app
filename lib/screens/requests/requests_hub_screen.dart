import 'package:flutter/material.dart';

import '../../models/fuel_request.dart';
import '../../models/recharge_request.dart';
import '../../services/request_service.dart';
import 'fuel_request_screen.dart';
import 'recharge_request_screen.dart';

const _brandPurple = Color(0xFF62109F);

enum _RequestKind { fuel, recharge }

class _RecentRequestEntry {
  final _RequestKind kind;
  final String title;
  final String subtitle;
  final String status;
  final String date;
  final DateTime? sortDate;

  _RecentRequestEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.date,
    required this.sortDate,
  });
}

class RequestsHubScreen extends StatefulWidget {
  const RequestsHubScreen({super.key, this.driverMobile});

  final String? driverMobile;

  @override
  State<RequestsHubScreen> createState() => _RequestsHubScreenState();
}

class _RequestsHubScreenState extends State<RequestsHubScreen> {
  final _service = RequestService();
  bool _loading = true;
  String? _error;
  List<_RecentRequestEntry> _entries = [];
  FuelAssignedVehicle? _vehicle;
  String _filter = 'all'; // all | pending | completed

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _parseDate(String? dateOnly, String date) {
    if (dateOnly != null && dateOnly.isNotEmpty) {
      final parsed = DateTime.tryParse(dateOnly);
      if (parsed != null) return parsed;
    }
    // Fallback: "d/m/Y, H:i:s"
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})').firstMatch(date);
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      final year = int.tryParse(match.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchFuelRequests(),
        _service.fetchRechargeRequests(),
      ]);
      final fuelResult = results[0]
          as ({
            List<FuelRequestItem> history,
            List<FuelRequestItem> pending,
            FuelAssignedVehicle? vehicle,
          });
      final rechargeResult =
          results[1] as ({List<RechargeRequestItem> history, List<RechargeRequestItem> pending});

      final entries = <_RecentRequestEntry>[
        ...fuelResult.history.map(
          (f) => _RecentRequestEntry(
            kind: _RequestKind.fuel,
            title: 'Fuel Request',
            subtitle: [
              if (f.orders != null) '${f.orders} orders',
              if (f.fuelType != null && f.fuelType!.isNotEmpty) f.fuelType!,
            ].join(' • '),
            status: f.status,
            date: f.date,
            sortDate: _parseDate(f.dateOnly, f.date),
          ),
        ),
        ...rechargeResult.history.map(
          (r) => _RecentRequestEntry(
            kind: _RequestKind.recharge,
            title: 'Internet Recharge',
            subtitle: [
              if (r.mobile != null && r.mobile!.isNotEmpty) 'Mobile: ${r.mobile}',
              if (r.operatorName != null && r.operatorName!.isNotEmpty) r.operatorName!,
            ].join(' • '),
            status: r.status,
            date: r.date,
            sortDate: _parseDate(r.dateOnly, r.date),
          ),
        ),
      ];
      entries.sort((a, b) {
        final ad = a.sortDate;
        final bd = b.sortDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _vehicle = fuelResult.vehicle;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_RecentRequestEntry> get _filteredEntries {
    if (_filter == 'pending') {
      return _entries.where((e) => e.status.toLowerCase() == 'pending').toList();
    }
    if (_filter == 'completed') {
      return _entries.where((e) => e.status.toLowerCase() != 'pending').toList();
    }
    return _entries;
  }

  void _handleSubmitResult(({bool success, String? message})? result) {
    if (result == null || !result.success) return;
    _load();
    if (result.message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message!)),
      );
    }
  }

  Future<void> _openFuelRequest() async {
    final result = await Navigator.push<({bool success, String? message})>(
      context,
      MaterialPageRoute(builder: (_) => FuelRequestScreen(vehicle: _vehicle)),
    );
    _handleSubmitResult(result);
  }

  Future<void> _openRechargeRequest() async {
    final result = await Navigator.push<({bool success, String? message})>(
      context,
      MaterialPageRoute(
        builder: (_) => RechargeRequestScreen(initialMobile: widget.driverMobile),
      ),
    );
    _handleSubmitResult(result);
  }

  void _showNewRequestSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.local_gas_station, color: _brandPurple),
                title: const Text('Fuel Request'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openFuelRequest();
                },
              ),
              ListTile(
                leading: const Icon(Icons.signal_cellular_alt, color: _brandPurple),
                title: const Text('Internet Recharge'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openRechargeRequest();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        backgroundColor: _brandPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewRequestSheet,
        backgroundColor: _brandPurple,
        icon: const Icon(Icons.add),
        label: const Text('New request'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const Text(
            'What do you need?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RequestTypeCard(
                  icon: Icons.local_gas_station,
                  title: 'Fuel Request',
                  subtitle: 'Request fuel for your assigned vehicle',
                  onTap: _openFuelRequest,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RequestTypeCard(
                  icon: Icons.signal_cellular_alt,
                  title: 'Internet Recharge',
                  subtitle: 'Request a mobile data recharge',
                  onTap: _openRechargeRequest,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'My recent requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Pending',
                selected: _filter == 'pending',
                onTap: () => setState(() => _filter = 'pending'),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Completed',
                selected: _filter == 'completed',
                onTap: () => setState(() => _filter = 'completed'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          else if (_filteredEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: _brandPurple.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No requests yet',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            )
          else
            ..._filteredEntries.map((e) => _RecentRequestCard(entry: e)),
        ],
      ),
    );
  }
}

class _RequestTypeCard extends StatelessWidget {
  const _RequestTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: _brandPurple.withValues(alpha: 0.08),
              child: Icon(icon, color: _brandPurple, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: _brandPurple,
                child: Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _brandPurple,
      labelStyle: TextStyle(color: selected ? Colors.white : _brandPurple),
      backgroundColor: Colors.white,
      shape: StadiumBorder(side: BorderSide(color: _brandPurple.withValues(alpha: 0.4))),
    );
  }
}

class _RecentRequestCard extends StatelessWidget {
  const _RecentRequestCard({required this.entry});

  final _RecentRequestEntry entry;

  (Color, Color) _statusColors(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return (Colors.orange.shade50, Colors.orange.shade800);
      case 'approved':
      case 'recharged':
        return (Colors.green.shade50, Colors.green.shade800);
      case 'rejected':
        return (Colors.red.shade50, Colors.red.shade800);
      default:
        return (Colors.grey.shade100, Colors.grey.shade700);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _statusColors(entry.status);
    final icon = entry.kind == _RequestKind.fuel
        ? Icons.local_gas_station
        : Icons.signal_cellular_alt;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _brandPurple.withValues(alpha: 0.08),
              child: Icon(icon, color: _brandPurple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        entry.date,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.$1,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.status,
                      style: TextStyle(
                        color: colors.$2,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
