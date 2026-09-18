/// Pure classification of a set of physical tiles into a meld type, used by
/// the results screen's inline meld-selection mode (see `scan_screen.dart`'s
/// `_buildMeldSection`) to decide chi/pon/kan without asking the user to pick
/// a type explicitly — the type is fully determined by which tiles they
/// selected.
enum MeldDetection { none, pon, chi, kan }

/// Parses a numbered tile code (e.g. `3p`, `5mr`) into its `(rank, suit)`,
/// treating a red five as rank 5 of its suit for sequence/triplet purposes.
/// Returns null for anything else (honors, or an unrecognized code) — same
/// code-format rules as `tileAssetPath` in `tile_assets.dart`.
(int, String)? _parseNumbered(String code) {
  final redMatch = RegExp(r'^5([smpr])r$').firstMatch(code);
  if (redMatch != null) return (5, redMatch.group(1)!);

  if (RegExp(r'^[1-9][mps]$').hasMatch(code)) {
    return (int.parse(code[0]), code[1]);
  }
  return null;
}

/// Classifies [tileCodes] (as resolved from `ConfirmedMeld.observationIds`,
/// e.g. via `_tileCodeForObservationId`) into pon/chi/kan, or `none` if the
/// set doesn't form a valid meld. Order-independent. Kakan (加槓) is
/// intentionally not detected here — it's out of scope for inline selection.
MeldDetection detectMeldType(List<String> tileCodes) {
  if (tileCodes.length == 4) {
    return tileCodes.every((code) => code == tileCodes.first)
        ? MeldDetection.kan
        : MeldDetection.none;
  }

  if (tileCodes.length == 3) {
    if (tileCodes.every((code) => code == tileCodes.first)) {
      return MeldDetection.pon;
    }

    final parsed = tileCodes.map(_parseNumbered).toList();
    if (parsed.any((tile) => tile == null)) return MeldDetection.none;
    final suits = parsed.map((tile) => tile!.$2).toSet();
    if (suits.length != 1) return MeldDetection.none;

    final ranks = parsed.map((tile) => tile!.$1).toList()..sort();
    final isSequential =
        ranks.toSet().length == 3 && ranks[2] - ranks[0] == 2;
    return isSequential ? MeldDetection.chi : MeldDetection.none;
  }

  return MeldDetection.none;
}
