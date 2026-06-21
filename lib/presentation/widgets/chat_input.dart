import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../domain/models/attachment.dart';
import '../../theme/app_theme.dart';
import '../bloc/chat_bloc.dart';

/// Maximum number of characters a single outgoing message may contain. Caps
/// untrusted user input before it is base64/JSON-encoded and sent to the
/// backend, bounding request size.
const int kMaxMessageLength = 8000;

class ChatInput extends StatefulWidget {
  final Function(String) onSend;

  const ChatInput({super.key, required this.onSend});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    var text = _controller.text.trim();
    if (text.isEmpty) return;
    // Belt-and-suspenders: clamp length even if the field's formatter is bypassed.
    if (text.length > kMaxMessageLength) {
      text = text.substring(0, kMaxMessageLength);
    }
    widget.onSend(text);
    // Text clear is handled reactively by ChatBloc (setting state.inputText to "")
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatBloc, ChatState>(
      listenWhen: (previous, current) =>
          previous.inputText != current.inputText,
      listener: (context, state) {
        // Keeps the text controller in sync with the BLoC's state without setState()
        if (_controller.text != state.inputText) {
          _controller.text = state.inputText;
          // Set cursor position at the end of the text
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
      },
      child: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          bool hasText = state.inputText.trim().isNotEmpty;
          bool isListening = state.isListening;

          return Container(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
              top: 8,
            ),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFF242424,
                      ), // Sleek ChatGPT dark gray capsule
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.pendingAttachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 8,
                              left: 10,
                              right: 10,
                              bottom: 4,
                            ),
                            child: _buildAttachmentPreviews(context, state),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        // Attachment Icon Button
                        IconButton(
                          icon: Icon(
                            LucideIcons.plus,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 20,
                          ),
                          onPressed: () {
                            _showAttachmentOptions(context);
                          },
                        ),
                        const SizedBox(width: 4),
                        // Main Input field
                        Expanded(
                          child: isListening
                              ? Container(
                                  height: 48,
                                  alignment: Alignment.centerLeft,
                                  child: const Row(
                                    children: [
                                      VoiceWaveform(),
                                      SizedBox(width: 12),
                                      Text(
                                        "Listening...",
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : TextField(
                                  controller: _controller,
                                  maxLines: 5,
                                  minLines: 1,
                                  maxLength: kMaxMessageLength,
                                  maxLengthEnforcement:
                                      MaxLengthEnforcement.enforced,
                                  buildCounter:
                                      (
                                        context, {
                                        required currentLength,
                                        required maxLength,
                                        required isFocused,
                                      }) => null,
                                  keyboardType: TextInputType.multiline,
                                  onChanged: (text) {
                                    // Reactively dispatch text updates to ChatBloc
                                    context.read<ChatBloc>().add(
                                      UpdateInputText(text),
                                    );
                                  },
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "Message Zenith AI...",
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 4,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 4),
                        // Mic button
                        IconButton(
                          icon: Icon(
                            isListening
                                ? LucideIcons.circle_stop
                                : LucideIcons.mic,
                            color: isListening
                                ? AppTheme.primaryColor
                                : Colors.white.withValues(alpha: 0.6),
                            size: 20,
                          ),
                          onPressed: () {
                            // Reactively dispatch speech action
                            context.read<ChatBloc>().add(
                              const ToggleSpeechListening(),
                            );
                          },
                        ),
                        const SizedBox(width: 2),
                        // Send button (dynamic appearance driven by ChatState)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(bottom: 2),
                          child: IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: hasText
                                  ? AppTheme
                                        .primaryColor // emerald green when active
                                  : Colors.white.withValues(
                                      alpha: 0.08,
                                    ), // dark/muted when empty
                              foregroundColor: hasText
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(10),
                              minimumSize: const Size(40, 40),
                            ),
                            icon: const Icon(LucideIcons.arrow_up, size: 18),
                            onPressed: hasText ? _handleSend : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAttachmentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(LucideIcons.image, color: Colors.white70),
                  title: const Text(
                    "Upload from library",
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImages();
                  },
                ),
                ListTile(
                  leading: const Icon(
                    LucideIcons.file_text,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    "Attach document",
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickDocuments();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: true,
      );
      if (result == null || !mounted) return;

      final bloc = context.read<ChatBloc>();
      for (final file in result.files) {
        if (file.bytes == null) continue;
        bloc.add(
          AttachmentPicked(
            MessageAttachment(
              type: AttachmentType.image,
              filename: file.name,
              mimeType: _mimeFromExtension(file.extension, isImage: true),
              bytes: file.bytes!,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    } finally {
      // Returning from the native file picker can leave keyboard focus in a
      // stuck state on some mobile platforms, making the text field
      // unresponsive to taps until focus is released.
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    }
  }

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'txt'],
        withData: true,
        allowMultiple: true,
      );
      if (result == null || !mounted) return;

      final bloc = context.read<ChatBloc>();
      for (final file in result.files) {
        if (file.bytes == null) continue;
        bloc.add(
          AttachmentPicked(
            MessageAttachment(
              type: AttachmentType.document,
              filename: file.name,
              mimeType: _mimeFromExtension(file.extension),
              bytes: file.bytes!,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick document: $e')),
        );
      }
    } finally {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    }
  }

  String _mimeFromExtension(String? extension, {bool isImage = false}) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      default:
        return isImage ? 'image/jpeg' : 'application/octet-stream';
    }
  }

  Widget _buildAttachmentPreviews(BuildContext context, ChatState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 64,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: state.pendingAttachments.length,
          itemBuilder: (context, index) {
            final attachment = state.pendingAttachments[index];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _AttachmentPreviewItem(
                attachment: attachment,
                onRemove: () {
                  context.read<ChatBloc>().add(AttachmentRemoved(index));
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// A single pending attachment preview with a remove ("x") badge.
class _AttachmentPreviewItem extends StatelessWidget {
  final MessageAttachment attachment;
  final VoidCallback onRemove;

  const _AttachmentPreviewItem({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.type == AttachmentType.image;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: isImage ? 56 : 140,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF333333),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.memory(
                  attachment.bytes,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.file_text,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          attachment.filename,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFF424242),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// Gorgeous voice input waveform animation
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({super.key});

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Generates beautiful staggered heights
            final double value = math.sin(
              (_controller.value * 2 * math.pi) + (index * 0.6),
            );
            final double height = 6 + (value.abs() * 18);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.0),
              width: 3.0,
              height: height,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}
