import 'canonical_json.dart';

/// One section's difference, in the operator's language.
class BundleSectionDiff {
  final String label;
  final int added;
  final int removed;
  final int changed;

  const BundleSectionDiff({
    required this.label,
    this.added = 0,
    this.removed = 0,
    this.changed = 0,
  });

  bool get isEmpty => added == 0 && removed == 0 && changed == 0;

  /// Phrased from the remote copy's point of view, because that is what the
  /// operator is deciding whether to take: "3 more people" means their copy
  /// has three this machine does not.
  String get summary {
    final parts = <String>[
      if (added > 0) '$added more',
      if (removed > 0) '$removed missing',
      if (changed > 0) '$changed changed',
    ];
    return '$label: ${parts.join(', ')}';
  }
}

/// What differs between this machine's configuration and another's.
class BundleDiff {
  final List<BundleSectionDiff> sections;

  const BundleDiff(this.sections);

  bool get isEmpty => sections.every((s) => s.isEmpty);

  List<String> get lines =>
      [for (final s in sections) if (!s.isEmpty) s.summary];

  static const Map<String, String> _listSections = {
    'positions': 'Positions',
    'people': 'People',
    'services': 'Services',
    'heightRanges': 'Height ranges',
    'operators': 'Operator panels',
  };

  static const Map<String, String> _mapSections = {
    'presetNames': 'Preset labels',
    'visibilities': 'Button visibility',
  };

  static BundleDiff between(
    Map<String, dynamic> mine,
    Map<String, dynamic> theirs,
  ) {
    final sections = <BundleSectionDiff>[];

    _listSections.forEach((field, label) {
      sections.add(_diffIdList(label, mine[field], theirs[field]));
    });

    _mapSections.forEach((field, label) {
      sections.add(_diffKeyedMap(label, mine[field], theirs[field]));
    });

    // No ids to key on: cameras are a name/address list and the switcher is a
    // single string. Same-or-different is all this can honestly say.
    final camerasDiffer = canonicalJsonEncode(mine['cameras']) !=
        canonicalJsonEncode(theirs['cameras']);
    if (camerasDiffer) {
      sections.add(const BundleSectionDiff(label: 'Camera addresses', changed: 1));
    }
    if (mine['rolandIp'] != theirs['rolandIp']) {
      sections.add(
          const BundleSectionDiff(label: 'Switcher address', changed: 1));
    }

    return BundleDiff(sections);
  }

  static BundleSectionDiff _diffIdList(
      String label, Object? mineRaw, Object? theirsRaw) {
    Map<String, String> index(Object? raw) {
      if (raw is! List) return const {};
      final out = <String, String>{};
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        // Fall back to position for anything without an id, so an unkeyed
        // list still reports "changed" rather than silently reading equal.
        final key = item is Map && item['id'] is String
            ? item['id'] as String
            : 'index:$i';
        out[key] = canonicalJsonEncode(item);
      }
      return out;
    }

    final mine = index(mineRaw);
    final theirs = index(theirsRaw);
    return BundleSectionDiff(
      label: label,
      added: theirs.keys.where((k) => !mine.containsKey(k)).length,
      removed: mine.keys.where((k) => !theirs.containsKey(k)).length,
      changed: theirs.entries
          .where((e) => mine.containsKey(e.key) && mine[e.key] != e.value)
          .length,
    );
  }

  static BundleSectionDiff _diffKeyedMap(
      String label, Object? mineRaw, Object? theirsRaw) {
    // Counted by BUTTON, not by device. Twenty renamed presets on one camera
    // is "20 changed", not "1 changed": an undercount here is exactly the
    // "three unlabelled buttons" problem in a different costume.
    int innerCount(Object? raw, bool Function(String device, String item) keep) {
      if (raw is! Map) return 0;
      var n = 0;
      raw.forEach((device, items) {
        if (items is! Map) return;
        for (final item in items.keys) {
          if (keep('$device', '$item')) n++;
        }
      });
      return n;
    }

    Object? item(Object? raw, String device, String key) {
      if (raw is! Map) return null;
      final items = raw[device];
      return items is Map ? items[key] : null;
    }

    return BundleSectionDiff(
      label: label,
      added: innerCount(theirsRaw,
          (d, i) => item(mineRaw, d, i) == null),
      removed: innerCount(mineRaw,
          (d, i) => item(theirsRaw, d, i) == null),
      changed: innerCount(
          theirsRaw,
          (d, i) =>
              item(mineRaw, d, i) != null &&
              canonicalJsonEncode(item(mineRaw, d, i)) !=
                  canonicalJsonEncode(item(theirsRaw, d, i))),
    );
  }
}
