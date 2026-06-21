import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/core/security/attachment_validator.dart';

void main() {
  group('isAllowedMimeType', () {
    test('accepts backend allow-listed types', () {
      expect(AttachmentValidator.isAllowedMimeType('image/png'), isTrue);
      expect(AttachmentValidator.isAllowedMimeType('image/jpeg'), isTrue);
      expect(AttachmentValidator.isAllowedMimeType('image/webp'), isTrue);
      expect(AttachmentValidator.isAllowedMimeType('image/gif'), isTrue);
      expect(AttachmentValidator.isAllowedMimeType('application/pdf'), isTrue);
      expect(AttachmentValidator.isAllowedMimeType('text/plain'), isTrue);
    });

    test('rejects types the backend doesn\'t accept', () {
      expect(AttachmentValidator.isAllowedMimeType('application/octet-stream'), isFalse);
      expect(AttachmentValidator.isAllowedMimeType('application/zip'), isFalse);
      expect(AttachmentValidator.isAllowedMimeType('video/mp4'), isFalse);
    });
  });

  group('isValidPdf', () {
    test('accepts a %PDF header', () {
      final bytes = Uint8List.fromList(
        [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34], // %PDF-1.4
      );
      expect(AttachmentValidator.isValidPdf(bytes), isTrue);
    });

    test('rejects non-PDF bytes', () {
      expect(
        AttachmentValidator.isValidPdf(Uint8List.fromList([0x00, 0x01, 0x02])),
        isFalse,
      );
      expect(AttachmentValidator.isValidPdf(Uint8List(0)), isFalse);
    });
  });

  group('isValidUtf8Text', () {
    test('accepts valid UTF-8', () {
      expect(
        AttachmentValidator.isValidUtf8Text(
          Uint8List.fromList(utf8.encode('hello, wörld 🌍')),
        ),
        isTrue,
      );
    });

    test('rejects malformed/binary bytes', () {
      // 0xC3 starts a 2-byte sequence but 0x28 is not a valid continuation.
      expect(
        AttachmentValidator.isValidUtf8Text(
          Uint8List.fromList([0xC3, 0x28, 0xA0, 0xFF]),
        ),
        isFalse,
      );
    });
  });

  group('documentRejectionReason', () {
    test('accepts a real PDF', () {
      final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(
        AttachmentValidator.documentRejectionReason('application/pdf', pdf),
        isNull,
      );
    });

    test('rejects a binary renamed as .pdf', () {
      final fake = Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00]); // MZ (exe)
      expect(
        AttachmentValidator.documentRejectionReason('application/pdf', fake),
        isNotNull,
      );
    });

    test('rejects binary masquerading as text', () {
      final fake = Uint8List.fromList([0xC3, 0x28, 0xFF]);
      expect(
        AttachmentValidator.documentRejectionReason('text/plain', fake),
        isNotNull,
      );
    });

    test('rejects empty and unsupported types', () {
      expect(
        AttachmentValidator.documentRejectionReason('application/pdf', Uint8List(0)),
        isNotNull,
      );
      expect(
        AttachmentValidator.documentRejectionReason(
          'application/octet-stream',
          Uint8List.fromList([1, 2, 3]),
        ),
        isNotNull,
      );
    });
  });
}
