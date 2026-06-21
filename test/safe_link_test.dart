import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/core/security/safe_link.dart';

void main() {
  group('SafeLink.isAllowed', () {
    test('allows http, https and mailto', () {
      expect(SafeLink.isAllowed('https://example.com'), isTrue);
      expect(SafeLink.isAllowed('http://example.com/path?q=1'), isTrue);
      expect(SafeLink.isAllowed('mailto:someone@example.com'), isTrue);
    });

    test('is case-insensitive on the scheme', () {
      expect(SafeLink.isAllowed('HTTPS://example.com'), isTrue);
    });

    test('blocks dangerous schemes', () {
      expect(SafeLink.isAllowed('javascript:alert(1)'), isFalse);
      expect(SafeLink.isAllowed('data:text/html,<script>'), isFalse);
      expect(SafeLink.isAllowed('file:///etc/passwd'), isFalse);
      expect(SafeLink.isAllowed('intent://scan/#Intent;end'), isFalse);
      expect(SafeLink.isAllowed('content://contacts'), isFalse);
      expect(SafeLink.isAllowed('tel:+15551234567'), isFalse);
      expect(SafeLink.isAllowed('myapp://open'), isFalse);
    });

    test('rejects schemeless / malformed input', () {
      expect(SafeLink.isAllowed(''), isFalse);
      expect(SafeLink.isAllowed('   '), isFalse);
      expect(SafeLink.isAllowed('example.com'), isFalse);
      expect(SafeLink.isAllowed('//example.com'), isFalse);
    });
  });
}
