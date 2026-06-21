import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// URL schemes we are willing to open from AI-generated markdown content.
///
/// Everything else (javascript:, data:, file:, intent:, content:, tel:, app
/// deep-link schemes, ...) is rejected. Assistant responses are untrusted input
/// — a link like `[click](javascript:...)` or `[doc](file:///etc/passwd)` must
/// never be handed to the platform launcher.
const Set<String> kAllowedUrlSchemes = {'http', 'https', 'mailto'};

/// Safely handles a link tapped inside rendered markdown.
///
/// Validates the scheme against [kAllowedUrlSchemes], then asks the user to
/// confirm the *full* destination before launching it externally — so a link
/// whose visible text disagrees with its target can't silently send the user
/// somewhere unexpected.
class SafeLink {
  const SafeLink._();

  /// Returns true if [href] parses and uses an allowed scheme.
  static bool isAllowed(String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return false;
    if (uri.scheme.isEmpty) return false;
    return kAllowedUrlSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Validates and (after user confirmation) opens [href].
  static Future<void> open(BuildContext context, String href) async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = href.trim();
    final uri = Uri.tryParse(trimmed);

    if (uri == null || !isAllowed(trimmed)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This link type is blocked for your safety.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open external link?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This link will open outside the app:'),
            const SizedBox(height: 12),
            SelectableText(
              uri.toString(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')),
      );
    }
  }
}
