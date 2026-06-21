import 'dart:typed_data';

enum AttachmentType { image, document }

class MessageAttachment {
  final AttachmentType type;
  final String filename;
  final String mimeType;
  final Uint8List bytes;

  const MessageAttachment({
    required this.type,
    required this.filename,
    required this.mimeType,
    required this.bytes,
  });
}
