/// Anything that has local changes waiting to be uploaded. The dashboard's
/// sync runs every pusher (in order) before downloading from the server.
///
/// Order matters: medications must reach the server before the dose logs
/// that point to them.
abstract interface class SyncPusher {
  /// Uploads pending rows. Throws (e.g. DioException) when it cannot reach
  /// the server; the rows stay pending and are retried next sync.
  Future<void> pushPending();
}
