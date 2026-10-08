import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import '../models/height_range.dart';
import '../models/panasonic_camera_config.dart';
import '../models/person.dart';
import '../models/position.dart';
import '../models/service.dart';
import '../services/abstract/roland_service_abstract.dart';
import '../services/lineup_store.dart';
import '../services/preset_name_store.dart';
import '../utils/label_utils.dart';
import '../utils/preset_resolver.dart';

class _FlatStep {
  final String id;
  final StepType type;
  final String? participantId;
  final String? positionId;
  final int? macroNumber;
  final String? cameraIp;
  final int? cameraPresetIndex;

  const _FlatStep({
    required this.id,
    required this.type,
    this.participantId,
    this.positionId,
    this.macroNumber,
    this.cameraIp,
    this.cameraPresetIndex,
  });
}

class ServiceTab extends StatefulWidget {
  final List<PanasonicCameraConfig> cameras;
  final List<Person> people;
  final List<Position> positions;
  final List<Service> services;
  final List<HeightRange> heightRanges;
  final RolandServiceAbstract? rolandService;
  final ValueNotifier<bool>? rolandConnected;
  final TextEditingController? rolandIpController;
  final ValueChanged<String> onResponse;
  /// Where failures go. Falls back to [onResponse] when not given, so a
  /// caller that only wants text still gets every message.
  final ValueChanged<String>? onFailure;

  const ServiceTab({
    super.key,
    required this.cameras,
    required this.people,
    required this.positions,
    required this.services,
    required this.heightRanges,
    required this.rolandService,
    required this.rolandConnected,
    required this.onResponse,
    this.onFailure,
    this.rolandIpController,
  });

  @override
  State<ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends State<ServiceTab> {

  void _fail(String message) =>
      (widget.onFailure ?? widget.onResponse)(message);
  String? _selectedServiceId;
  int? _currentStepIndex;

  // cue key (see [_cueKey]) → outcome of its most recent firing. Keyed by
  // step, not list position: a step recorded above a fired cue would
  // otherwise move its check onto a cue that never ran.
  final Map<String, _CueState> _cueStates = {};
  // Bumped whenever the cue list is swapped out, so a command that finishes
  // afterwards cannot stamp its outcome onto a different service's cue.
  int _cueGeneration = 0;

  // "serviceId/cueKey" for every cue whose command is still out. Unlike
  // [_cueStates] it survives a service switch or re-pick, and — being
  // static — the tab being rebuilt when the operator flips to Panel and
  // back. Losing it let a second tap send the same command again, and a
  // toggle macro flips back.
  static final Set<String> _inFlight = {};

  // Bumped when [_inFlight] changes, so a tab rebuilt while a cue was out
  // stops its spinner when the command the old tab sent finishes.
  static final ValueNotifier<int> _inFlightChanges = ValueNotifier(0);

  void _onInFlightChanged() {
    if (mounted) setState(() {});
  }

  String _inFlightKey(String cueKey) => '$_selectedServiceId/$cueKey';

  // participantId → personId, set at run time for this service and kept in
  // LineupStore so the day's lineup outlives this widget
  final Map<String, String?> _participantAssignments = {};

  // A remembered service whose id has not yet appeared in widget.services
  // (the page loads services asynchronously).
  String? _pendingServiceId;

  Map<int, String> _rolandNames = {};
  Map<String, Map<int, String>> _cameraNames = {};

  String? _lastRolandKey;
  Set<String>? _lastCameraIps;

  @override
  void initState() {
    super.initState();
    _lastRolandKey = _rolandKey;
    _lastCameraIps = _cameraIps;
    _loadNames();
    _inFlightChanges.addListener(_onInFlightChanged);
    _restoreSelection();
    LineupStore.expirations.addListener(_onLineupExpired);
  }

  @override
  void dispose() {
    _inFlightChanges.removeListener(_onInFlightChanged);
    LineupStore.expirations.removeListener(_onLineupExpired);
    super.dispose();
  }

  /// The stored lineup lapsed while this tab sat on screen with the screen
  /// off. Drop the copy shown here too, or it would outlive the one deleted.
  void _onLineupExpired() {
    if (!mounted) return;
    setState(_participantAssignments.clear);
  }

  Future<void> _restoreSelection() async {
    final id = await LineupStore.loadSelectedServiceId();
    if (id == null || !mounted || _selectedServiceId != null) return;
    if (widget.services.any((s) => s.id == id)) {
      _selectService(id);
    } else {
      _pendingServiceId = id;
    }
  }

  void _selectService(String? id) {
    _pendingServiceId = null;
    setState(() {
      _selectedServiceId = id;
      _currentStepIndex = null;
      // A command still out for the old service must not stamp its outcome
      // onto a cue in this one.
      _cueStates.clear();
      _cueGeneration++;
      _participantAssignments.clear();
    });
    LineupStore.saveSelectedServiceId(id);
    if (id != null) _loadLineup(id);
  }

  Future<void> _loadLineup(String serviceId) async {
    final saved = await LineupStore.load(serviceId);
    if (!mounted || _selectedServiceId != serviceId) return;
    // Anything the operator picked while this was loading wins.
    setState(() {
      for (final e in saved.entries) {
        _participantAssignments.putIfAbsent(e.key, () => e.value);
      }
    });
  }

  Future<void> _assign(String participantId, String? personId) async {
    final serviceId = _selectedServiceId;
    if (serviceId == null) return;
    // Renew first. If the lineup lapsed — the screen woke before the renew
    // timer ran — that clears the stale copy shown here, so the save below
    // cannot hand yesterday's readers a fresh 20 minutes.
    await LineupStore.renew();
    if (!mounted || _selectedServiceId != serviceId) return;
    setState(() => _participantAssignments[participantId] = personId);
    await LineupStore.save(serviceId, Map.of(_participantAssignments));
  }

  String get _rolandKey => 'roland_${widget.rolandIpController?.text ?? ''}';

  Set<String> get _cameraIps =>
      widget.cameras.map((c) => c.ipController.text).toSet();

  Future<void> _loadNames() async {
    final cameraIps = widget.cameras.map((c) => c.ipController.text).toList();
    final results = await Future.wait([
      PresetNameStore.loadAll(_rolandKey),
      ...cameraIps.map(PresetNameStore.loadAll),
    ]);
    final roland = results.first;
    final cameraNames = <String, Map<int, String>>{
      for (var i = 0; i < cameraIps.length; i++) cameraIps[i]: results[i + 1],
    };
    if (mounted) {
      setState(() {
        _rolandNames = roland;
        _cameraNames = cameraNames;
      });
    }
  }

  /// "name (N)" for macro [macroNumber] if a custom name is saved, otherwise
  /// just "Macro N".
  String _macroLabel(int macroNumber) => formatItemLabel(
      _rolandNames[macroNumber], '$macroNumber',
      fallback: 'Macro $macroNumber');

  /// "name (N)" for [presetIndex] (0-based) on [cameraIp] if a custom name is
  /// saved, otherwise just "Preset N" (1-based).
  String _presetLabel(String cameraIp, int presetIndex) {
    final n = presetIndex + 1;
    return formatItemLabel(_cameraNames[cameraIp]?[presetIndex], '$n',
        fallback: 'Preset $n');
  }

  Service? get _selectedService => _selectedServiceId == null
      ? null
      : widget.services.where((s) => s.id == _selectedServiceId).firstOrNull;

  List<_FlatStep> get _flatSteps {
    final service = _selectedService;
    if (service == null) return [];
    return _flatten(service, {});
  }

  List<_FlatStep> _flatten(Service service, Set<String> visited) {
    if (visited.contains(service.id)) return [];
    final seen = {...visited, service.id};
    final result = <_FlatStep>[];
    for (final s in service.steps) {
      if (s.type == StepType.block && s.subServiceId != null) {
        final sub = widget.services
            .where((sv) => sv.id == s.subServiceId)
            .firstOrNull;
        if (sub != null) result.addAll(_flatten(sub, seen));
      } else {
        result.add(_FlatStep(
          id: s.id,
          type: s.type,
          participantId: s.participantId,
          positionId: s.positionId,
          macroNumber: s.macroNumber,
          cameraIp: s.cameraIp,
          cameraPresetIndex: s.cameraPresetIndex,
        ));
      }
    }
    return result;
  }

  /// Identifies the cue at [index]: its step id, plus which occurrence of
  /// that step it is, since a block used twice repeats the same steps.
  static String _cueKey(List<_FlatStep> flat, int index) {
    final id = flat[index].id;
    var occurrence = 0;
    for (var i = 0; i < index; i++) {
      if (flat[i].id == id) occurrence++;
    }
    return '$id#$occurrence';
  }

  Set<String> get _referencedParticipantIds {
    return _flatSteps
        .where((s) => s.type == StepType.ministry && s.participantId != null)
        .map((s) => s.participantId!)
        .toSet();
  }

  @override
  void didUpdateWidget(ServiceTab old) {
    super.didUpdateWidget(old);
    if (_selectedServiceId != null &&
        !widget.services.any((s) => s.id == _selectedServiceId)) {
      _selectedServiceId = null;
      _currentStepIndex = null;
      _cueStates.clear();
      _cueGeneration++;
      _participantAssignments.clear();
    }
    final pending = _pendingServiceId;
    if (pending != null && widget.services.any((s) => s.id == pending)) {
      // Deferred past this frame: setState is not allowed mid-update.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingServiceId == pending) _selectService(pending);
      });
    }

    // The parent loads the Roland IP and camera list asynchronously and can
    // change them at any time (e.g. Settings -> Connections) while this tab
    // stays mounted; reload names whenever the effective config actually
    // changes rather than only once in initState.
    final key = _rolandKey;
    final ips = _cameraIps;
    if (key != _lastRolandKey || !setEquals(ips, _lastCameraIps)) {
      _lastRolandKey = key;
      _lastCameraIps = ips;
      _loadNames();
    }
  }

  Future<void> _fireStep(int index) async {
    final flat = _flatSteps;
    if (index < 0 || index >= flat.length) return;
    // A second tap on a cue still in flight would send the command twice.
    final key = _cueKey(flat, index);
    final flightKey = _inFlightKey(key);
    if (_inFlight.contains(flightKey)) {
      setState(() => _currentStepIndex = index);
      return;
    }
    final generation = _cueGeneration;
    _inFlight.add(flightKey);
    setState(() {
      _currentStepIndex = index;
      _cueStates[key] = _CueState.executing;
    });
    final s = flat[index];

    final bool ok;
    try {
      ok = switch (s.type) {
        StepType.ministry => await _fireMinistryStep(s),
        StepType.macro => await _fireMacroStep(s),
        StepType.shot => await _fireShotStep(s),
        StepType.block => true, // already flattened; should never appear
      };
    } finally {
      _inFlight.remove(flightKey);
      _inFlightChanges.value++;
    }
    if (!mounted) return;
    if (generation != _cueGeneration) {
      // Stops the spinner shown if the operator switched back meanwhile.
      setState(() {});
      return;
    }
    setState(() =>
        _cueStates[key] = ok ? _CueState.succeeded : _CueState.failed);
  }

  Future<bool> _fireMinistryStep(_FlatStep s) async {
    final service = _selectedService;
    final participant = s.participantId == null
        ? null
        : service?.participants
            .where((p) => p.id == s.participantId)
            .firstOrNull;
    if (participant == null) {
      _fail('Missing participant data');
      return false;
    }
    final personId = _participantAssignments[participant.id];
    if (personId == null) {
      _fail(
          'No one assigned to "${participant.name}" for this service');
      return false;
    }
    final person = widget.people.where((p) => p.id == personId).firstOrNull;
    final position = s.positionId == null
        ? null
        : widget.positions.where((p) => p.id == s.positionId).firstOrNull;
    if (person == null || position == null) {
      _fail('Missing person or position data');
      return false;
    }
    if (s.cameraIp == null) {
      _fail(
          '${participant.name} · ${position.name} has no camera set');
      return false;
    }
    final camera = widget.cameras
        .where((c) => c.ipController.text == s.cameraIp)
        .firstOrNull;
    if (camera == null) {
      _fail('Camera not found (${s.cameraIp})');
      return false;
    }
    final presetIndex = resolvePreset(
      person: person,
      positionId: position.id,
      cameraIp: camera.ipController.text,
      heightRanges: widget.heightRanges,
    );
    if (presetIndex == null) {
      _fail(
          '${person.name} has no preset for ${camera.name} at "${position.name}"');
      return false;
    }
    if (!camera.isConnected.value || camera.service == null) {
      _fail('${camera.name} not connected');
      return false;
    }
    try {
      final response = await camera.service!.recallPreset(presetIndex);
      widget.onResponse(
          '${participant.name} (${person.name}) · ${position.name} → ${camera.name}: $response');
      return true;
    } catch (e) {
      _fail('Error: $e');
      return false;
    }
  }

  Future<bool> _fireMacroStep(_FlatStep s) async {
    if (s.macroNumber == null) {
      _fail('Macro number not set');
      return false;
    }
    final connected = widget.rolandConnected?.value ?? false;
    if (!connected || widget.rolandService == null) {
      _fail('Roland not connected');
      return false;
    }
    try {
      await widget.rolandService!.executeMacro(s.macroNumber!);
      widget.onResponse('${_macroLabel(s.macroNumber!)} executed');
      return true;
    } catch (e) {
      _fail('Macro error: $e');
      return false;
    }
  }

  Future<bool> _fireShotStep(_FlatStep s) async {
    if (s.cameraIp == null || s.cameraPresetIndex == null) {
      _fail('Camera or preset not set');
      return false;
    }
    final camera = widget.cameras
        .where((c) => c.ipController.text == s.cameraIp)
        .firstOrNull;
    if (camera == null) {
      _fail('Camera not found (${s.cameraIp})');
      return false;
    }
    if (!camera.isConnected.value || camera.service == null) {
      _fail('${camera.name} not connected');
      return false;
    }
    try {
      final response = await camera.service!.recallPreset(s.cameraPresetIndex!);
      widget.onResponse(
          '${camera.name} → ${_presetLabel(s.cameraIp!, s.cameraPresetIndex!)}: $response');
      return true;
    } catch (e) {
      _fail('Error: $e');
      return false;
    }
  }

  void _goNext() {
    final flat = _flatSteps;
    if (flat.isEmpty) return;
    final next =
        (_currentStepIndex == null ? 0 : _currentStepIndex! + 1)
            .clamp(0, flat.length - 1);
    _fireStep(next);
  }

  void _goPrev() {
    if (_currentStepIndex == null || _currentStepIndex! == 0) return;
    _fireStep(_currentStepIndex! - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.services.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_list_numbered, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('No services configured',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Use Settings → Manage Services to create one',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final flat = _flatSteps;
    final service = _selectedService;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildServiceDropdown(),
        ),

        if (service != null && _referencedParticipantIds.isNotEmpty)
          _buildParticipantAssignmentPanel(),

        Expanded(
          child: service == null
              ? const Center(
                  child: Text('Select a service above',
                      style: TextStyle(color: Colors.grey)))
              : flat.isEmpty
                  ? const Center(
                      child: Text('This service has no steps',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: flat.length,
                      itemBuilder: (context, i) =>
                          _buildStepTile(flat[i], i, _cueKey(flat, i)),
                    ),
        ),

        if (service != null && flat.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: (_currentStepIndex ?? 0) > 0 ? _goPrev : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Prev'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: _currentStepIndex == null
                        ? const Text('Tap a step or Next to begin',
                            style: TextStyle(color: Colors.grey))
                        : Text(
                            '${_currentStepIndex! + 1} / ${flat.length}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: (_currentStepIndex == null ||
                          _currentStepIndex! < flat.length - 1)
                      ? _goNext
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildServiceDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Service',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedServiceId,
          isDense: true,
          isExpanded: true,
          hint: const Text('Select service…',
              style: TextStyle(color: Colors.grey)),
          items: widget.services
              .map((s) => DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(s.name),
                  ))
              .toList(),
          onChanged: _selectService,
        ),
      ),
    );
  }

  Widget _buildParticipantAssignmentPanel() {
    final service = _selectedService;
    if (service == null) return const SizedBox.shrink();

    final participants = _referencedParticipantIds
        .map((id) =>
            service.participants.where((p) => p.id == id).firstOrNull)
        .whereType<Participant>()
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Today's cast",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...participants.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(p.name,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            // A remembered person may since have been
                            // deleted; a value with no matching item would
                            // throw.
                            value: widget.people.any((person) =>
                                    person.id == _participantAssignments[p.id])
                                ? _participantAssignments[p.id]
                                : null,
                            isDense: true,
                            isExpanded: true,
                            hint: const Text('— unassigned —',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— unassigned —',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              ...widget.people.map((person) =>
                                  DropdownMenuItem<String?>(
                                    value: person.id,
                                    child: Text(person.name),
                                  )),
                            ],
                            onChanged: (personId) => _assign(p.id, personId),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStepTile(_FlatStep s, int index, String cueKey) {
    final isCurrent = _currentStepIndex == index;
    final service = _selectedService;

    String title = '${index + 1}. ';
    String? subtitle;
    bool hasWarning = false;
    IconData typeIcon = Icons.circle_outlined;

    switch (s.type) {
      case StepType.ministry:
        final participant = s.participantId == null
            ? null
            : service?.participants
                .where((p) => p.id == s.participantId)
                .firstOrNull;
        final position = s.positionId == null
            ? null
            : widget.positions
                .where((p) => p.id == s.positionId)
                .firstOrNull;
        typeIcon = Icons.badge;
        if (participant == null || position == null) {
          title += 'Missing participant/position';
          hasWarning = true;
        } else {
          final camera = s.cameraIp == null
              ? null
              : widget.cameras
                  .where((c) => c.ipController.text == s.cameraIp)
                  .firstOrNull;
          if (camera == null) {
            title += '${participant.name}  ·  ${position.name}  ·  camera not set';
            hasWarning = true;
          } else {
            title += '${participant.name}  ·  ${position.name}  ·  ${camera.name}';
            final personId = _participantAssignments[participant.id];
            if (personId == null) {
              subtitle = '${participant.name} not assigned';
              hasWarning = true;
            } else {
              final person =
                  widget.people.where((p) => p.id == personId).firstOrNull;
              subtitle = person?.name ?? 'Unknown person';
            }
          }
        }

      case StepType.macro:
        typeIcon = Icons.settings_remote;
        title += s.macroNumber != null
            ? _macroLabel(s.macroNumber!)
            : 'Macro (not set)';
        if (s.macroNumber == null) hasWarning = true;

      case StepType.shot:
        typeIcon = Icons.videocam;
        final camera = s.cameraIp == null
            ? null
            : widget.cameras
                .where((c) => c.ipController.text == s.cameraIp)
                .firstOrNull;
        if (camera == null || s.cameraPresetIndex == null) {
          title += 'Shot (not set)';
          hasWarning = true;
        } else {
          title +=
              '${camera.name}  ·  ${_presetLabel(s.cameraIp!, s.cameraPresetIndex!)}';
        }

      case StepType.block:
        typeIcon = Icons.subdirectory_arrow_right;
        title += 'Block';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isCurrent
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: switch (_inFlight.contains(_inFlightKey(cueKey))
            ? _CueState.executing
            : _cueStates[cueKey]) {
          _CueState.executing => const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          _CueState.succeeded =>
            const Icon(Icons.check_circle, color: Colors.green),
          _CueState.failed => const Icon(Icons.error, color: Colors.red),
          null => isCurrent
              ? Icon(Icons.play_arrow,
                  color: Theme.of(context).colorScheme.primary)
              : Icon(typeIcon, size: 18, color: Colors.grey.shade500),
        },
        title: Text(title,
            style: TextStyle(
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.normal)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: hasWarning
            ? const Icon(Icons.warning_amber, color: Colors.orange)
            : null,
        onTap: () => _fireStep(index),
      ),
    );
  }
}

/// Where a fired cue stands, shown on its tile so the operator can tell a
/// slow camera from a dead one.
enum _CueState { executing, succeeded, failed }
