/// Which subsystem a fault came from.
enum FaultDomain { backup, roland, camera }

enum BackupFailureKind {
  offline,
  authExpired,
  permissionDenied,
  rateLimited,
  transientServer,
  storageFull,
  storageWriteFailed,
  conflict,
  adoptionChoice,
  unsupportedSchema,
  malformedRemote,
  targetMissing,
  deviceUnnamed,
  unknown,
}

/// Any failure or warning the app wants to surface.
class AppFault implements Exception {
  final FaultDomain domain;

  /// Stable, domain-specific identifier. Never free text — the log collapses
  /// on it, so it must not vary between two occurrences of the same problem.
  final String kind;

  /// Human-readable, shown in the popover. May contain varying detail.
  final String message;

  /// Which operation was in flight: 'push', 'pull', 'prune'.
  final String? operation;

  /// Which storage target this happened against.
  final String? targetIdentity;

  final Object? cause;

  const AppFault({
    required this.domain,
    required this.kind,
    required this.message,
    this.operation,
    this.targetIdentity,
    this.cause,
  });

  factory AppFault.backup(
    BackupFailureKind kind,
    String message, {
    String? operation,
    String? targetIdentity,
    Object? cause,
  }) =>
      AppFault(
        domain: FaultDomain.backup,
        kind: kind.name,
        message: message,
        operation: operation,
        targetIdentity: targetIdentity,
        cause: cause,
      );

  /// A device the app was driving has dropped off: the switcher's link went
  /// down, or a camera stopped answering. [device] names it, and is what
  /// keeps two cameras' faults apart.
  factory AppFault.device(FaultDomain domain, String device, String message) {
    assert(domain != FaultDomain.backup);
    return AppFault(
      domain: domain,
      kind: deviceDisconnectedKind,
      message: message,
      operation: 'link',
      targetIdentity: device,
    );
  }

  static const deviceDisconnectedKind = 'deviceDisconnected';

  static const _promptRetry = {'offline', 'rateLimited', 'transientServer'};
  static const _sweepOnly = {'unknown'};
  static const _needsHuman = {
    'authExpired',
    'permissionDenied',
    'storageFull',
    'storageWriteFailed',
    'unsupportedSchema',
    'targetMissing',
    'malformedRemote',
    'conflict',
    'adoptionChoice',
    'deviceUnnamed',
    deviceDisconnectedKind,
  };

  /// Retryable, but only on the slow periodic sweep. A tight backoff loop
  /// around a permanent programmer error would spin forever.
  bool get sweepOnly => _sweepOnly.contains(kind);

  /// Whether waiting and trying again can fix this without a human.
  bool get isRetryable => _promptRetry.contains(kind) || sweepOnly;

  bool get needsUserAction => _needsHuman.contains(kind);

  /// Log collapsing key, per the spec: domain, kind, operation, target.
  String get fingerprint =>
      '${domain.name}/$kind/${operation ?? "-"}/${targetIdentity ?? "-"}';

  @override
  String toString() => 'AppFault(${domain.name}/$kind): $message';
}
