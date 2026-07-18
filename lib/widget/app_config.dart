import 'package:flutter/foundation.dart';
import 'web_helper.dart' as web_helper;

/// App configuration constants
class AppConfig {
  /// Get the email redirect URL based on platform
  /// Returns the URL where users should be redirected after clicking email links
  static String getEmailRedirectUrl() {
    if (kIsWeb) {
      // On web, use the current origin
      final currentUrl = web_helper.getCurrentUrl();
      if (currentUrl.isNotEmpty) {
        final uri = Uri.parse(currentUrl);
        return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      }
    }
    // Default fallback for local development
    return 'http://localhost:3000';
  }

  // TODO: Update this when you have a production domain
  // static const String productionSiteUrl = 'https://your-app-domain.com';
}

