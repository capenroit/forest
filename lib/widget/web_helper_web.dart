// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Get current browser URL (web only)
String getCurrentUrl() => html.window.location.href;

/// Replace the current URL without adding to history
void replaceUrl(String url) {
  html.window.history.replaceState(null, '', url);
}

