import 'package:flutter/material.dart';
import '../models/recognize_result.dart';
import '../services/api_client.dart';

/// All valid mahjong tile codes grouped by suit.
const _tileGroups = <String, List<String>>{
  '萬子': ['1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m'],
  '筒子': ['1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p'],
  '索子': ['1s', '2s', '3s', '4s', '5s', '6s', '7s', '8s', '9s'],
  '字牌': ['E', 'S', 'W', 'N', 'P', 'F', 'C'],
};

const _tileDisplayNames = <String, String>{
  '1m': '一萬', '2m': '二萬', '3m': '三萬', '4m': '四萬', '5m': '五萬',
  '6m': '六萬', '7m': '七萬', '8m': '八萬', '9m': '九萬',
  '1p': '一筒', '2p': '二筒', '3p': '三筒', '4p': '四筒', '5p': '五筒',
  '6p': '六筒', '7p': '七筒', '8p': '八筒', '9p': '九筒',
  '1s': '一索', '2s': '二索', '3s': '三索', '4s': '四索', '5s': '五索',
  '6s': '六索', '7s': '七索', '8s': '八索', '9s': '九索',
  'E': '東', 'S': '南', 'W': '西', 'N': '北',
  'P': '白', 'F': '發', 'C': '中',
};

class FeedbackScreen extends StatefulWidget {
  final RecognizeResponse recognition;

  const FeedbackScreen({super.key, required this.recognition});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late List<String> _correctedTiles;
  int? _editingIndex;
  bool _isSending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _correctedTiles = List.from(widget.recognition.handEstimate.topTiles);
    // Ensure exactly 14 tiles
    while (_correctedTiles.length < 14) {
      _correctedTiles.add('1m');
    }
    if (_correctedTiles.length > 14) {
      _correctedTiles = _correctedTiles.sublist(0, 14);
    }
  }

  Future<void> _submit() async {
    setState(() => _isSending = true);
    try {
      final api = ApiClient();
      await api.sendRecognitionFeedback(
        recognitionResponse: widget.recognition.rawJson,
        correctedTiles: _correctedTiles,
      );
      if (mounted) {
        setState(() {
          _sent = true;
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('フィードバックを送信しました')),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信エラー: $e')),
        );
      }
    }
  }

  void _selectTile(int index) {
    setState(() {
      _editingIndex = _editingIndex == index ? null : index;
    });
  }

  void _replaceTile(String tileCode) {
    if (_editingIndex == null) return;
    setState(() {
      _correctedTiles[_editingIndex!] = tileCode;
      _editingIndex = null;
    });
  }

  bool get _hasChanges {
    final original = widget.recognition.handEstimate.topTiles;
    if (_correctedTiles.length != original.length) return true;
    for (int i = 0; i < _correctedTiles.length; i++) {
      if (i >= original.length || _correctedTiles[i] != original[i]) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final originalTiles = widget.recognition.handEstimate.topTiles;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('認識フィードバック'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Original tiles
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black54,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '認識結果（元）',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: originalTiles
                        .map((t) => _staticTileBadge(t, Colors.white70))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),

          // Corrected tiles (editable)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '修正後（タップして変更）',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_correctedTiles.length, (i) {
                      final isEditing = _editingIndex == i;
                      final isChanged = i < originalTiles.length &&
                          _correctedTiles[i] != originalTiles[i];
                      return _editableTileBadge(
                        _correctedTiles[i],
                        i,
                        isEditing: isEditing,
                        isChanged: isChanged,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          // Tile picker (shown when editing)
          if (_editingIndex != null)
            Expanded(child: _buildTilePicker()),

          if (_editingIndex == null)
            const Spacer(),

          // Submit button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isSending || _sent || !_hasChanges)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  foregroundColor: Colors.black87,
                  disabledBackgroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _sent
                        ? const Text('送信済み')
                        : Text(_hasChanges
                            ? 'フィードバックを送信'
                            : '牌をタップして修正してください'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staticTileBadge(String tile, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(right: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tile,
        style: TextStyle(fontSize: 14, color: textColor),
      ),
    );
  }

  Widget _editableTileBadge(
    String tile,
    int index, {
    required bool isEditing,
    required bool isChanged,
  }) {
    return GestureDetector(
      onTap: () => _selectTile(index),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isEditing
              ? Colors.amberAccent
              : isChanged
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: isEditing
              ? Border.all(color: Colors.amber, width: 2)
              : isChanged
                  ? Border.all(color: Colors.greenAccent, width: 1.5)
                  : null,
        ),
        child: Text(
          tile,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isEditing ? Colors.black : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTilePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView(
        children: _tileGroups.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.value.map((tileCode) {
                  final displayName = _tileDisplayNames[tileCode] ?? tileCode;
                  return GestureDetector(
                    onTap: () => _replaceTile(tileCode),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            tileCode,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
