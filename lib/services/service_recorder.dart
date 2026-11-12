import 'package:flutter/foundation.dart';

import '../models/service.dart';

/// One live recording of a sequence of actions into a reusable [Service].
///
/// Shared by every tab that can fire an action, so a single recording can mix
/// switcher macros (Panel tab) with role-at-position shots (Positions tab).
///
/// A Positions-tab tap fires a real person, but a reusable service needs the
/// role they are playing. [recordMinistry] stores the role as a [Participant]
/// so the saved step resolves to whoever fills that role on the day.
class ServiceRecorder extends ChangeNotifier {
  bool _isRecording = false;
  final List<ServiceStep> _steps = [];
  final List<Participant> _participants = [];

  /// personId → participantId, so the second time the same person is tapped
  /// the role prompt can default to the role they were given the first time.
  final Map<String, String> _roleByPerson = {};

  int _idCounter = 0;

  /// Fixed for the life of one recording, so retrying a save that already
  /// half-landed replaces that copy instead of adding a second one.
  String _serviceId = generateServiceId();

  /// The tab that owned this recorder can be torn down while its save dialog
  /// is still open; the dialog's follow-up calls must not throw.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// Capturing: actions fired now are added as steps. Turns off the moment
  /// Stop is pressed, so nothing fired during or after a save sneaks in.
  bool get isRecording => _isRecording;

  /// Steps held after Stop that are not saved yet (a failed or pending save).
  bool get hasUnsaved => !_isRecording && _steps.isNotEmpty;

  /// Anything in progress: capturing, holding unsaved steps, or saving. The
  /// top-bar indicator shows while this is true, and a new recording can't
  /// start over it.
  bool get isActive => _isRecording || _steps.isNotEmpty || _isSaving;

  /// The id the saved Service gets. Also used to remove a half-landed copy
  /// if the operator then discards.
  String get serviceId => _serviceId;

  /// True while a save of this recording is being written. The Stop button
  /// is disabled so a second tap can't start a second, racing save.
  bool get isSaving => _isSaving;
  bool _isSaving = false;
  set isSaving(bool value) {
    _isSaving = value;
    notifyListeners();
  }

  List<ServiceStep> get steps => List.unmodifiable(_steps);
  List<Participant> get participants => List.unmodifiable(_participants);

  /// The role name this person was given earlier in this recording, if any.
  String? roleNameFor(String personId) {
    final pid = _roleByPerson[personId];
    if (pid == null) return null;
    return _participants.where((p) => p.id == pid).firstOrNull?.name;
  }

  /// Starts a fresh recording. Does nothing while one is active (capturing or
  /// holding unsaved steps), so a second Record can't wipe them.
  void start() {
    if (isActive) return;
    _clear();
    _serviceId = generateServiceId();
    _isRecording = true;
    notifyListeners();
  }

  /// Picks capturing back up, keeping the steps (the name dialog was closed
  /// without a choice).
  void resume() {
    _isRecording = true;
    notifyListeners();
  }

  /// Stops capturing. Steps are kept until [clear] so they can still be saved.
  void stop() {
    _isRecording = false;
    notifyListeners();
  }

  void clear() {
    _clear();
    notifyListeners();
  }

  /// Adds a fully-formed step (a Roland macro or a fixed camera preset).
  void recordStep(ServiceStep step) {
    if (!_isRecording) return;
    _steps.add(step);
    notifyListeners();
  }

  /// Adds a "role at position" step. [roleName] is matched case-insensitively
  /// against roles already used in this recording, so "Lector" and "lector "
  /// become the same participant.
  void recordMinistry({
    required String roleName,
    required String personId,
    required String positionId,
    required String cameraIp,
  }) {
    if (!_isRecording) return;
    final name = roleName.trim();
    if (name.isEmpty) return;

    final key = name.toLowerCase();
    var participant = _participants
        .where((p) => p.name.trim().toLowerCase() == key)
        .firstOrNull;
    if (participant == null) {
      participant = Participant(id: _nextId('role'), name: name);
      _participants.add(participant);
    }
    _roleByPerson[personId] = participant.id;

    _steps.add(ServiceStep(
      id: _nextId('step'),
      type: StepType.ministry,
      participantId: participant.id,
      positionId: positionId,
      cameraIp: cameraIp,
    ));
    notifyListeners();
  }

  /// The recording as a [Service] named [name].
  Service toService(String name) => Service(
        id: _serviceId,
        name: name,
        participants: List.of(_participants),
        steps: List.of(_steps),
      );

  void _clear() {
    _isRecording = false;
    _isSaving = false;
    _steps.clear();
    _participants.clear();
    _roleByPerson.clear();
  }

  String _nextId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
}
