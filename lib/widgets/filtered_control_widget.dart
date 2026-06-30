import 'package:flutter/material.dart';
import '../models/panasonic_camera_config.dart';
import '../models/controllable_device.dart';
import '../models/roland_device.dart';
import '../models/panasonic_device.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/visibility_store.dart';

/// Shows only items whose saved [ItemVisibility] matches [filter].
///
/// Items with no saved visibility default to [ItemVisibility.expanded], so the
/// Advanced page (filter = expanded) shows everything not explicitly tagged
/// otherwise, while the Basic page (filter = basic) shows only items the user
/// has explicitly marked as basic.
class FilteredControlWidget extends StatefulWidget {
  final String title;
  final ItemVisibility filter;
  final RolandServiceAbstract? rolandService;
  final ValueNotifier<bool>? rolandConnected;
  final TextEditingController? rolandIpController;
  final List<PanasonicCameraConfig> cameras;
  final ValueChanged<String> onResponse;

  const FilteredControlWidget({
    super.key,
    required this.title,
    required this.filter,
    required this.rolandService,
    required this.rolandConnected,
    required this.cameras,
    required this.onResponse,
    this.rolandIpController,
  });

  @override
  State<FilteredControlWidget> createState() => _FilteredControlWidgetState();
}

class _FilteredControlWidgetState extends State<FilteredControlWidget> {
  late final List<ControllableDevice> _devices;
  int _selectedDeviceIndex = 0;

  final Map<int, Map<int, String>> _namesByDevice = {};
  final Map<int, Map<int, ItemVisibility>> _visibilityByDevice = {};
  final List<VoidCallback> _deviceListeners = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _devices = [
      RolandDevice(
        service: () => widget.rolandService,
        connected: widget.rolandConnected ?? ValueNotifier(false),
        ip: () => widget.rolandIpController?.text ?? '',
      ),
      ...widget.cameras.map(PanasonicDevice.new),
    ];
    _setupDeviceListeners();
    _loadDeviceMetadata(_selectedDeviceIndex);
  }

  @override
  void dispose() {
    _removeDeviceListeners();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupDeviceListeners() {
    for (int i = 0; i < _devices.length; i++) {
      void listener() => _onDeviceConnectionChanged(i);
      _deviceListeners.add(listener);
      _devices[i].connectionListenable.addListener(listener);
    }
  }

  void _removeDeviceListeners() {
    for (int i = 0; i < _devices.length; i++) {
      _devices[i].connectionListenable.removeListener(_deviceListeners[i]);
    }
    _deviceListeners.clear();
  }

  void _onDeviceConnectionChanged(int deviceIndex) {
    if (_devices[deviceIndex].isConnected && _selectedDeviceIndex == deviceIndex) {
      _loadDeviceMetadata(deviceIndex);
      _refreshDevice();
    }
  }

  Future<void> _loadDeviceMetadata(int deviceIndex) async {
    final device = _devices[deviceIndex];
    final names = await device.loadNames();
    final visibility = await device.loadVisibility();
    if (mounted) {
      setState(() {
        _namesByDevice[deviceIndex] = names;
        _visibilityByDevice[deviceIndex] = visibility;
      });
    }
  }

  Future<void> _refreshDevice() async {
    final deviceIndex = _selectedDeviceIndex;
    final future = _devices[deviceIndex].refreshItems();
    if (mounted) setState(() {});
    try {
      await future;
    } catch (e) {
      if (mounted) widget.onResponse('Error fetching preset data: $e');
    }
    if (mounted) setState(() {});
  }

  void _onDeviceSelected(int index) {
    setState(() => _selectedDeviceIndex = index);
    _loadDeviceMetadata(index);
    _refreshDevice();
  }

  Future<void> _executeItem(int index) async {
    try {
      final msg = await _devices[_selectedDeviceIndex].execute(index);
      widget.onResponse(msg);
    } catch (e) {
      widget.onResponse('$e');
    }
  }

  static int _optimalCols(int count, double width, double height, double spacing) {
    int bestCols = 1;
    double bestArea = 0;
    for (int c = 1; c <= count; c++) {
      final r = (count / c).ceil();
      final bw = (width - (c - 1) * spacing) / c;
      final bh = (height - (r - 1) * spacing) / r;
      if (bw <= 0 || bh <= 0) continue;
      final area = bw * bh;
      if (area > bestArea) {
        bestArea = area;
        bestCols = c;
      }
    }
    return bestCols;
  }

  List<int> _filteredIndices(ControllableDevice device) {
    final visibility = _visibilityByDevice[_selectedDeviceIndex] ?? {};
    return device.itemIndices
        .where((i) => (visibility[i] ?? ItemVisibility.expanded) == widget.filter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final device = _devices[_selectedDeviceIndex];
    final names = _namesByDevice[_selectedDeviceIndex] ?? {};
    final indices = _filteredIndices(device);

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Device selector
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ToggleButtons(
                isSelected: List.generate(
                    _devices.length, (i) => i == _selectedDeviceIndex),
                onPressed: _onDeviceSelected,
                children: _devices
                    .map((d) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(d.name),
                        ))
                    .toList(),
              ),
            ),

            if (device.isLoadingItems) ...[
              const SizedBox(height: 8),
              const Row(children: [
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Loading presets...'),
              ]),
            ],

            const SizedBox(height: 12),

            Expanded(
              child: indices.isEmpty && !device.isLoadingItems
                  ? Center(
                      child: Text(
                        'No items tagged for ${widget.title.toLowerCase()} view.\nUse Master Control to assign items.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 4.0;
                        const maxCols = 5;
                        const maxVisibleRows = 5;
                        final cols = _optimalCols(
                          indices.length,
                          constraints.maxWidth,
                          constraints.maxHeight,
                          spacing,
                        ).clamp(1, maxCols);
                        final totalRows = (indices.length / cols).ceil();
                        final bw = (constraints.maxWidth - (cols - 1) * spacing) / cols;
                        final bh = (constraints.maxHeight - (maxVisibleRows - 1) * spacing) / maxVisibleRows;
                        return Scrollbar(
                          controller: _scrollController,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            child: Column(
                              children: List.generate(totalRows, (rowIdx) {
                            final start = rowIdx * cols;
                            final end = (start + cols).clamp(0, indices.length);
                            final rowItems = indices.sublist(start, end);
                            return Padding(
                              padding: EdgeInsets.only(top: rowIdx == 0 ? 0 : spacing),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: rowItems.asMap().entries.map((e) {
                                  final label = names[e.value] ?? device.defaultLabel(e.value);
                                  return Padding(
                                    padding: EdgeInsets.only(left: e.key == 0 ? 0 : spacing),
                                    child: SizedBox(
                                      width: bw,
                                      height: bh,
                                      child: Tooltip(
                                        message: label,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8.0)),
                                            padding: const EdgeInsets.all(8.0),
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          onPressed: () => _executeItem(e.value),
                                          child: FittedBox(
                                            fit: BoxFit.contain,
                                            child: Text(label, textAlign: TextAlign.center),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                              }),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
