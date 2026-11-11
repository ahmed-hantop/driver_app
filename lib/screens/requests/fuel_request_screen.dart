import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/fuel_request.dart';
import '../../services/request_service.dart';

const _brandPurple = Color(0xFF62109F);
const int _maxProofImageBytes = 5 * 1024 * 1024;

class FuelRequestScreen extends StatefulWidget {
  const FuelRequestScreen({super.key, this.vehicle});

  final FuelAssignedVehicle? vehicle;

  @override
  State<FuelRequestScreen> createState() => _FuelRequestScreenState();
}

class _FuelRequestScreenState extends State<FuelRequestScreen> {
  final _service = RequestService();
  final _ordersCtrl = TextEditingController();

  bool _checkingEligibility = true;
  bool _alreadyRequestedToday = false;
  bool _submitting = false;
  String? _error;

  Uint8List? _proofBytes;
  String? _proofFileName;

  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  @override
  void dispose() {
    _ordersCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility() async {
    try {
      final result = await _service.fetchFuelRequests();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final requestedToday = result.pending.any((f) => f.dateOnly == todayStr) ||
          result.history.any((f) => f.dateOnly == todayStr);
      if (!mounted) return;
      setState(() {
        _alreadyRequestedToday = requestedToday;
        _checkingEligibility = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingEligibility = false);
    }
  }

  void _showHistory() async {
    List<FuelRequestItem> history = [];
    bool loading = true;
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (loading) {
              _service.fetchFuelRequests().then((result) {
                setSheetState(() {
                  history = result.history;
                  loading = false;
                });
              }).catchError((e) {
                setSheetState(() {
                  error = e.toString();
                  loading = false;
                });
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (error != null) {
                  return Center(child: Text(error!));
                }
                if (history.isEmpty) {
                  return const Center(child: Text('No fuel requests yet'));
                }
                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final item = history[i];
                    return ListTile(
                      leading: const Icon(Icons.local_gas_station, color: _brandPurple),
                      title: Text('${item.orders ?? '-'} orders • ${item.fuelType ?? ''}'),
                      subtitle: Text(item.date),
                      trailing: Text(
                        item.status,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  ({Uint8List bytes, String fileName})? _normalizeImage(Uint8List sourceBytes) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      if (sourceBytes.lengthInBytes > _maxProofImageBytes) return null;
      return (
        bytes: sourceBytes,
        fileName: 'fuel_proof_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    }

    var current = decoded;
    const maxDimension = 1600;
    if (current.width > maxDimension || current.height > maxDimension) {
      current = img.copyResize(
        current,
        width: current.width >= current.height ? maxDimension : null,
        height: current.height > current.width ? maxDimension : null,
        interpolation: img.Interpolation.average,
      );
    }

    var quality = 88;
    var encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
    while (encoded.lengthInBytes > _maxProofImageBytes &&
        (quality > 45 || current.width > 720 || current.height > 720)) {
      if (current.width > 720 || current.height > 720) {
        final scaledWidth = max(1, (current.width * 0.85).round());
        final scaledHeight = max(1, (current.height * 0.85).round());
        current = img.copyResize(
          current,
          width: scaledWidth,
          height: scaledHeight,
          interpolation: img.Interpolation.average,
        );
      }
      quality = max(45, quality - 8);
      encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
    }

    if (encoded.lengthInBytes > _maxProofImageBytes) return null;
    return (
      bytes: encoded,
      fileName: 'fuel_proof_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
  }

  Future<void> _pickProof() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    if (source == ImageSource.camera) {
      final ok = await _ensureCameraPermission();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required.')),
        );
        return;
      }
    }

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final normalized = _normalizeImage(bytes);
      if (normalized == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image is too large. Please choose a smaller one.')),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _proofBytes = normalized.bytes;
        _proofFileName = normalized.fileName;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick an image. Please try again.')),
      );
    }
  }

  Future<void> _submit() async {
    final ordersText = _ordersCtrl.text.trim();
    final orders = int.tryParse(ordersText);
    if (orders == null || orders < 1) {
      setState(() => _error = 'Enter the number of orders delivered today.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await _service.submitFuelRequest(
      totalOrders: orders,
      proofImageBytes: _proofBytes,
      proofImageName: _proofFileName,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      Navigator.pop(context, (success: true, message: 'Fuel request sent successfully!'));
      return;
    }

    setState(() => _error = result.message ?? 'Failed to submit fuel request.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel Request'),
        backgroundColor: _brandPurple,
        foregroundColor: Colors.white,
      ),
      body: _checkingEligibility
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _brandPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: _brandPurple),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _alreadyRequestedToday
                              ? 'You have already submitted a fuel request today.'
                              : 'One fuel request is allowed per day.',
                          style: const TextStyle(color: _brandPurple),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Vehicle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _brandPurple.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.directions_car, color: _brandPurple),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.vehicle == null
                                    ? 'No vehicle assigned'
                                    : [
                                        widget.vehicle!.name ?? 'Vehicle',
                                        if (widget.vehicle!.plateNumber != null)
                                          widget.vehicle!.plateNumber!,
                                      ].join(' • '),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (widget.vehicle?.fuelType != null)
                                Text(
                                  'Fuel type: ${widget.vehicle!.fuelType}',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Request details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ordersCtrl,
                  enabled: !_alreadyRequestedToday,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Delivered orders today',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Proof of deliveries (optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _alreadyRequestedToday ? null : _pickProof,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border.all(color: _brandPurple.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(12),
                      color: _proofBytes != null ? Colors.green.shade50 : Colors.grey.shade50,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _proofBytes != null ? Icons.check_circle : Icons.upload_outlined,
                          color: _proofBytes != null ? Colors.green.shade700 : _brandPurple,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _proofFileName ?? 'Tap to upload screenshot',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add one screenshot, up to 5 MB',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _showHistory,
                    child: const Text('View fuel request history'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_submitting || _alreadyRequestedToday) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit fuel request'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Your request will be sent for approval.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
    );
  }
}
