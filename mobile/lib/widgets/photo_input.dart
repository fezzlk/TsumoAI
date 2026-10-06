import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Browser capture is a one-shot file picker, never a live camera stream.
class PhotoInput extends StatelessWidget {
  const PhotoInput({super.key, required this.busy, required this.onPick});
  final bool busy;
  final ValueChanged<ImageSource> onPick;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_photo_alternate_outlined, size: 72),
          const SizedBox(height: 20),
          Text('手牌の写真を読み込む', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            '牌がはっきり写った写真を選んでください。\n読み込み後に範囲や牌を修正できます。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (busy)
            const CircularProgressIndicator()
          else ...[
            FilledButton.icon(
              onPressed: () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('写真を選ぶ'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => onPick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('写真を撮る'),
            ),
          ],
        ],
      ),
    ),
  );
}
