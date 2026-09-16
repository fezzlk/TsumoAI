import 'package:flutter/material.dart';
import '../models/interpretation_request.dart';
import '../services/tile_assets.dart';

/// Image-based selection of which already-identified physical tiles form a
/// meld (chi/pon/kan), shown as a BottomSheet — same "pick from artwork,
/// not text" spirit as `TileImagePicker`, but here the choices are a
/// specific set of already-observed tile slots (which may repeat the same
/// tile code, e.g. two 5m), not the full 34-tile keyboard.
class MeldTilePicker extends StatefulWidget {
  final List<int> availableIndices;
  final String? Function(int index) tileCodeOf;

  const MeldTilePicker({
    super.key,
    required this.availableIndices,
    required this.tileCodeOf,
  });

  static Future<ConfirmedMeld?> show(
    BuildContext context, {
    required List<int> availableIndices,
    required String? Function(int index) tileCodeOf,
  }) {
    return showModalBottomSheet<ConfirmedMeld>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => MeldTilePicker(
        availableIndices: availableIndices,
        tileCodeOf: tileCodeOf,
      ),
    );
  }

  @override
  State<MeldTilePicker> createState() => _MeldTilePickerState();
}

class _MeldTilePickerState extends State<MeldTilePicker> {
  final Set<int> _selected = {};
  String _type = 'pon';
  bool _isOpen = true;

  int get _expected => {'chi', 'pon'}.contains(_type) ? 3 : 4;

  @override
  Widget build(BuildContext context) {
    // The confirm/cancel row is a FIXED footer, never inside the scrollable
    // part: an earlier version made the whole sheet (header..grid..buttons)
    // one scrollable column, but at this app's actual on-device landscape
    // size the buttons landed below the initial viewport by default —
    // reachable only by first discovering you can scroll a modal sheet
    // that also has its own drag-to-dismiss gesture, which nobody did.
    // Only the header/dropdown/switch/grid — the part whose height actually
    // varies with tile count (3-18, kan hands included) — scrolls, in the
    // space Flexible leaves after the fixed footer, so the buttons are
    // always on-screen without needing to scroll to find them.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '鳴き・槓を追加',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _type,
                      dropdownColor: Colors.grey.shade900,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: '種類'),
                      items: const [
                        DropdownMenuItem(value: 'chi', child: Text('チー')),
                        DropdownMenuItem(value: 'pon', child: Text('ポン')),
                        DropdownMenuItem(value: 'kan', child: Text('明槓')),
                        DropdownMenuItem(value: 'ankan', child: Text('暗槓')),
                        DropdownMenuItem(value: 'kakan', child: Text('加槓')),
                      ],
                      onChanged: (value) => setState(() {
                        _type = value!;
                        _isOpen = _type != 'ankan';
                        _selected.clear();
                      }),
                    ),
                    SwitchListTile(
                      title: const Text(
                        '副露（open）',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: _isOpen,
                      onChanged: _type == 'ankan'
                          ? null
                          : (value) => setState(() => _isOpen = value),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$_expected枚を選択（${_selected.length}/$_expected）',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.availableIndices.map((index) {
                        final code = widget.tileCodeOf(index);
                        final path = code == null
                            ? null
                            : tileAssetPath(code);
                        final isSelected = _selected.contains(index);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (isSelected) {
                              _selected.remove(index);
                            } else if (_selected.length < _expected) {
                              _selected.add(index);
                            }
                          }),
                          child: Container(
                            width: 48,
                            height: 64,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: isSelected
                                  ? Border.all(
                                      color: Colors.greenAccent,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: path == null
                                      ? const SizedBox.shrink()
                                      : Image.asset(path, fit: BoxFit.contain),
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.6,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _selected.length == _expected
                        ? () => Navigator.pop(
                            context,
                            ConfirmedMeld(
                              observationIds: _selected
                                  .map(
                                    (index) =>
                                        'tile-${index.toString().padLeft(3, '0')}',
                                  )
                                  .toList(growable: false),
                              type: _type,
                              open: _isOpen,
                            ),
                          )
                        : null,
                    child: const Text('確定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
