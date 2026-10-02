import '../models/interpretation_request.dart';
import '../models/scan_purpose.dart';

/// How the confirmed tiles must change when the results screen's
/// 「別の確認へ」 moves from one [ScanPurpose] to another.
///
/// Score and discard analysis work on a 14-tile hand, wait and call
/// analysis on a 13-tile hand. Kan tiles are on top of either base count,
/// so the adjustment depends only on the two purposes, never on how many
/// tiles happen to be on screen.
enum PurposeSwitchAdjustment {
  /// Same base count: the tiles are reused unchanged.
  none,

  /// 14 → 13: the user picks one concealed tile to leave out.
  removeOne,

  /// 13 → 14: the user picks one drawn tile to add.
  addOne,
}

PurposeSwitchAdjustment purposeSwitchAdjustment(
  ScanPurpose from,
  ScanPurpose to,
) {
  final delta = to.defaultTileCount - from.defaultTileCount;
  if (delta < 0) return PurposeSwitchAdjustment.removeOne;
  if (delta > 0) return PurposeSwitchAdjustment.addOne;
  return PurposeSwitchAdjustment.none;
}

String observationIdForSlot(int index) =>
    'tile-${index.toString().padLeft(3, '0')}';

int? slotForObservationId(String? id) =>
    id == null ? null : int.tryParse(id.split('-').last);

/// Removes [index] from a fixed-length slot list, shifting later slots one
/// position left and filling the freed last slot with [empty], so physical
/// slot order stays contiguous after a tile is left out.
void removeSlot<T>(List<T> slots, int index, T empty) {
  for (var i = index; i < slots.length - 1; i++) {
    slots[i] = slots[i + 1];
  }
  slots[slots.length - 1] = empty;
}

/// The observation id that referred to a later slot before [removedIndex]
/// was removed, renumbered to its shifted slot. Returns null when [id]
/// pointed at the removed slot itself.
String? shiftObservationIdAfterRemoval(String? id, int removedIndex) {
  final index = slotForObservationId(id);
  if (index == null) return id;
  if (index == removedIndex) return null;
  return index > removedIndex ? observationIdForSlot(index - 1) : id;
}

/// Confirmed melds renumbered after [removedIndex] was removed. A meld that
/// contained the removed tile no longer describes a complete set and is
/// dropped; callers only offer concealed tiles for removal, so in practice
/// every meld survives.
List<ConfirmedMeld> shiftMeldsAfterRemoval(
  List<ConfirmedMeld> melds,
  int removedIndex,
) {
  return [
    for (final meld in melds)
      if (!meld.observationIds.contains(observationIdForSlot(removedIndex)))
        ConfirmedMeld(
          observationIds: [
            for (final id in meld.observationIds)
              shiftObservationIdAfterRemoval(id, removedIndex)!,
          ],
          type: meld.type,
          open: meld.open,
        ),
  ];
}
