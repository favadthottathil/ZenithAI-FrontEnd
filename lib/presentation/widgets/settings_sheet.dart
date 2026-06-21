import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../core/security/screen_security.dart';
import '../../theme/app_theme.dart';

/// Bottom sheet with app settings. Currently exposes the privacy / screen
/// security toggle.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  /// Shows the settings sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SettingsSheet(),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  bool _secure = ScreenSecurity.instance.isEnabled;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Settings",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppTheme.primaryColor,
              secondary: Icon(
                LucideIcons.shield_check,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              title: const Text(
                "Hide chat from screenshots",
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: Text(
                "Blocks screenshots and blanks the app preview in the "
                "recent-apps switcher.",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12.5,
                ),
              ),
              value: _secure,
              onChanged: (value) async {
                setState(() => _secure = value);
                await ScreenSecurity.instance.setEnabled(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
