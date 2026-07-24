/// Stub implementation for non-web platforms
library;

String getCurrentUrl() => '';

void replaceUrl(String url) {}

void downloadBytes(List<int> bytes, String fileName, String mimeType) {
  throw UnsupportedError('downloadBytes is only supported on web');
}

