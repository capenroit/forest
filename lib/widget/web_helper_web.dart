// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Get current browser URL (web only)
String getCurrentUrl() => html.window.location.href;

/// Replace the current URL without adding to history
void replaceUrl(String url) {
  html.window.history.replaceState(null, '', url);
}

/// Trigger a browser file download for the given bytes (web only).
void downloadBytes(List<int> bytes, String fileName, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

