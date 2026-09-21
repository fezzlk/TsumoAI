import 'interpretation_request.dart';

/// The reason the user opened the shared camera flow.
///
/// Choosing this on Home lets the camera and result screens use the correct
/// default tile count without asking again after recognition.
enum ScanPurpose {
  score,
  wait,
  discard,
  callAdvice;

  int get defaultTileCount => switch (this) {
    ScanPurpose.score || ScanPurpose.discard => 14,
    ScanPurpose.wait || ScanPurpose.callAdvice => 13,
  };

  HandOperation get operation => switch (this) {
    ScanPurpose.score => HandOperation.score,
    ScanPurpose.wait => HandOperation.tenpai,
    // FEZ-215 will give call advice its own deterministic operation. Until
    // then it reuses the existing analysis capture/confirmation path.
    ScanPurpose.discard ||
    ScanPurpose.callAdvice => HandOperation.discardAnalysis,
  };

  String get label => switch (this) {
    ScanPurpose.score => '点数計算',
    ScanPurpose.wait => '待ち確認',
    ScanPurpose.discard => '何を切る？',
    ScanPurpose.callAdvice => '鳴き判断',
  };
}
