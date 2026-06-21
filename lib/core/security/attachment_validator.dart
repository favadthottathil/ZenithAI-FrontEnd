import 'dart:convert';
import 'dart:typed_data';

/// Content-based validation for picked attachments. File extensions and the
/// MIME types inferred from them are attacker-controllable (a binary can be
/// renamed `.txt`/`.pdf`), so before an attachment is accepted we verify the
/// raw bytes actually match the claimed type.
class AttachmentValidator {
  const AttachmentValidator._();

  /// MIME types the backend accepts for attachments (`POST /chat` and
  /// `/chat-stream`). Anything else is rejected by the backend with a 422,
  /// so attachments are checked against this allowlist before sending.
  static const Set<String> kAllowedAttachmentMimeTypes = {
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/gif',
    'application/pdf',
    'text/plain',
  };

  /// Whether the backend will accept an attachment with this MIME type.
  static bool isAllowedMimeType(String mimeType) =>
      kAllowedAttachmentMimeTypes.contains(mimeType);

  /// A PDF must begin with the `%PDF` magic header (0x25 0x50 0x44 0x46).
  static bool isValidPdf(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46; // F
  }

  /// A `.txt` attachment must decode cleanly as UTF-8 (no malformed bytes),
  /// which rejects binaries masquerading as plain text.
  static bool isValidUtf8Text(Uint8List bytes) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Validates a non-image (document) attachment by its claimed MIME type.
  /// Returns null when the bytes are acceptable, or a short reason string to
  /// surface to the user when they are not.
  static String? documentRejectionReason(String mimeType, Uint8List bytes) {
    if (bytes.isEmpty) return "That file appears to be empty.";
    switch (mimeType) {
      case 'application/pdf':
        return isValidPdf(bytes) ? null : "That file isn't a valid PDF.";
      case 'text/plain':
        return isValidUtf8Text(bytes) ? null : "That file isn't valid text.";
      default:
        // Unknown/unsupported document type — don't send unverified bytes.
        return "That file type isn't supported.";
    }
  }
}
