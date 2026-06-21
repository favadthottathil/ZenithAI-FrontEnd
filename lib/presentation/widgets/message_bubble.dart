import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/safe_link.dart';
import '../../domain/models/attachment.dart';
import '../../domain/models/message.dart';
import '../../theme/app_theme.dart';
import '../bloc/chat_bloc.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final int messageIndex;
  final bool isLast;
  final bool isStreaming;
  final String? errorMessage;

  const MessageBubble({
    super.key,
    required this.message,
    required this.messageIndex,
    this.isLast = false,
    this.isStreaming = false,
    this.errorMessage,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // Start cursor blink immediately for both thinking (empty) and streaming states
    if (widget.errorMessage == null &&
        (widget.isStreaming ||
            (widget.message.role == MessageRole.assistant &&
                widget.message.text.isEmpty))) {
      _cursorController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate =
        widget.errorMessage == null &&
        (widget.isStreaming ||
            (widget.message.role == MessageRole.assistant &&
                widget.message.text.isEmpty));
    if (shouldAnimate && !_cursorController.isAnimating) {
      _cursorController.repeat(reverse: true);
    } else if (!shouldAnimate && _cursorController.isAnimating) {
      _cursorController.stop();
      _cursorController.value = 0;
    }
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  // The model sometimes emits a list marker ("1.", "*", "-") on its own
  // line, with the item's content on the following line(s). CommonMark
  // treats that as an empty list item followed by a separate paragraph,
  // so the number/bullet and its title render as disconnected blocks.
  // Merge a lone marker line with the next non-empty line so it parses
  // as a single list item.
  String _formatText(String text) {
    final lines = text.split('\n');
    final markerOnly = RegExp(r'^(\d+[.)]|[*+-])$');
    final result = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (markerOnly.hasMatch(trimmed)) {
        var j = i + 1;
        while (j < lines.length && lines[j].trim().isEmpty) {
          j++;
        }
        if (j < lines.length) {
          result.add('$trimmed ${lines[j].trim()}');
          i = j;
          continue;
        }
      }
      result.add(lines[i]);
    }
    return result.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isLast = widget.isLast;
    final isStreaming = widget.isStreaming;
    final messageIndex = widget.messageIndex;

    bool isUser = message.role == MessageRole.user;
    bool isAssistant = message.role == MessageRole.assistant;
    bool isThinking = isAssistant && message.text.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) _buildAssistantAvatar(),
              if (!isUser) const SizedBox(width: 12),
               Flexible(
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (isUser && message.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildAttachments(message.attachments),
                      ),
                    if (message.text.isNotEmpty ||
                        (!isUser && message.attachments.isNotEmpty) ||
                        (isUser && message.attachments.isEmpty) ||
                        (!isUser && isThinking))
                      Container(
                        padding: isUser
                            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                            : const EdgeInsets.only(top: 4, bottom: 4, right: 16),
                        decoration: BoxDecoration(
                          color: isUser
                              ? const Color(0xFF2F2F2F) // Soft ChatGPT charcoal pill
                              : Colors.transparent, // Assistant content flows background-free
                          borderRadius: isUser
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                  bottomLeft: Radius.circular(20),
                                  bottomRight: Radius.circular(4),
                                )
                              : null,
                        ),
                        child: (isThinking && widget.errorMessage != null)
                            // The request failed before any text arrived
                            ? _buildErrorText(widget.errorMessage!)
                            : isThinking
                            // Waiting on the API: animated "thinking" dots
                            ? _buildThinkingIndicator()
                            : isStreaming
                            // Streaming: blinking cursor with text flowing in
                            ? _buildStreamingText(message.text)
                            // After streaming complete: full rich Markdown formatting
                            : _buildMarkdownContent(context, message.text),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Clean Action Buttons below Assistant Answer (only when fully typed)
          if (isAssistant &&
              !isThinking &&
              message.text.isNotEmpty &&
              !isStreaming)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 6),
              child: Row(
                children: [
                  _buildActionButton(
                    icon: LucideIcons.thumbs_up,
                    active: message.isLiked,
                    onTap: () {
                      context.read<ChatBloc>().add(
                        ToggleMessageLike(messageIndex),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: LucideIcons.thumbs_down,
                    active: message.isDisliked,
                    onTap: () {
                      context.read<ChatBloc>().add(
                        ToggleMessageDislike(messageIndex),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: LucideIcons.copy,
                    active: false,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        _actionSnackBar("Copied response to clipboard"),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: message.isSpeaking
                        ? LucideIcons.volume_x
                        : LucideIcons.volume_2,
                    active: message.isSpeaking,
                    onTap: () {
                      context.read<ChatBloc>().add(
                        ToggleMessageSpeaking(messageIndex),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        _actionSnackBar(
                          !message.isSpeaking
                              ? "Reading response aloud..."
                              : "Speech stopped",
                        ),
                      );
                    },
                  ),
                  if (isLast) ...[
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: LucideIcons.refresh_cw,
                      active: false,
                      onTap: () {
                        context.read<ChatBloc>().add(
                          const RegenerateResponse(),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          _actionSnackBar("Regenerating response..."),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Renders image previews and document chips attached to a user message.
  // Images are shown large (Gemini-style "card" above the prompt text):
  // a single image fills the available bubble width, while multiple images
  // share a 2-column grid of large tiles.
  Widget _buildAttachments(List<MessageAttachment> attachments) {
    final images = attachments
        .where((a) => a.type == AttachmentType.image)
        .toList();
    final documents = attachments
        .where((a) => a.type != AttachmentType.image)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (images.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 320.0;
              final isSingle = images.length == 1;
              final tileWidth = isSingle
                  ? maxWidth.clamp(0, 320).toDouble()
                  : ((maxWidth - 8) / 2).clamp(0, 200).toDouble();
              final tileHeight = isSingle ? 240.0 : tileWidth;

              return Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: images.map((attachment) {
                  final index = attachments.indexOf(attachment);
                  final heroTag =
                      'lightbox_${widget.messageIndex}_${index}_${attachment.filename}';
                  return GestureDetector(
                    onTap: () => _openLightbox(attachment, heroTag),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Hero(
                        tag: heroTag,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            attachment.bytes,
                            width: tileWidth,
                            height: tileHeight,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        if (documents.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: images.isNotEmpty ? 8 : 0),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: documents.map((attachment) {
                return Container(
                  constraints: const BoxConstraints(maxWidth: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.file_text,
                        color: AppTheme.primaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          attachment.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // Shown when the request failed before any response text arrived
  Widget _buildErrorText(String error) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.circle_alert, color: Colors.redAccent, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            "Something went wrong: $error",
            style: TextStyle(
              color: Colors.redAccent.withValues(alpha: 0.9),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // Splits text on "**bold**" markers into plain/bold TextSpans. Any
  // trailing unmatched "**" (mid-stream, before its closing pair has
  // arrived yet) is left as plain text until it closes.
  List<TextSpan> _parseBoldSpans(String text) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    int lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return spans;
  }

  // Shown while waiting for the first chunk of the API response: a
  // blinking cursor bar, matching the cursor used once text starts streaming.
  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FadeTransition(
        opacity: _cursorController,
        child: Container(
          width: 8,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  // Lightweight streaming text with smooth animated cursor — parses
  // "**bold**" inline so bold formatting renders live while streaming,
  // without the overhead of full markdown parsing.
  Widget _buildStreamingText(String text) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 15.5,
          height: 1.6,
          letterSpacing: 0.1,
        ),
        children: [
          ..._parseBoldSpans(text),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FadeTransition(
              opacity: _cursorController,
              child: Container(
                width: 8,
                height: 16,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Full rich Markdown rendering — only used when streaming has completed
  Widget _buildMarkdownContent(BuildContext context, String text) {
    return MarkdownBody(
      data: _formatText(text),
      onTapLink: (linkText, href, title) => SafeLink.open(context, href ?? ''),
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        blockSpacing: 16.0,
        p: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 15.5,
          height: 1.6,
          letterSpacing: 0.1,
        ),
        code: GoogleFonts.firaCode(
          backgroundColor: const Color(0xFF0F0F0F),
          color: const Color(0xFF38BDF8),
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        codeblockPadding: const EdgeInsets.all(14),
        strong: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15.5,
        ),
        h1: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        h1Padding: const EdgeInsets.only(top: 20, bottom: 8),
        h2Padding: const EdgeInsets.only(top: 16, bottom: 6),
        h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
        listBullet: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 15.5,
        ),
        listBulletPadding: const EdgeInsets.only(right: 8, top: 2),
        listIndent: 20.0,
      ),
    );
  }

  Widget _buildAssistantAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          LucideIcons.sparkles,
          color: AppTheme.primaryColor,
          size: 15,
        ),
      ),
    );
  }

  // A short confirmation toast for message actions (copy/speak/regenerate).
  // It floats with a bottom margin large enough to clear the chat input bar,
  // so the grey snackbar never overlaps/hides the text field.
  SnackBar _actionSnackBar(String message) {
    return SnackBar(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: AppTheme.surfaceColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: active
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 14,
            color: active
                ? AppTheme.primaryColor
                : AppTheme.mutedTextColor.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  void _openLightbox(MessageAttachment attachment, String heroTag) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.9),
        pageBuilder: (context, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white, size: 24),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(LucideIcons.download, color: Colors.white, size: 20),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("File: ${attachment.filename}"),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppTheme.surfaceColor,
                      ),
                    );
                  },
                ),
              ],
            ),
            body: Center(
              child: InteractiveViewer(
                clipBehavior: Clip.none,
                minScale: 0.5,
                maxScale: 4.0,
                child: Hero(
                  tag: heroTag,
                  child: Image.memory(
                    attachment.bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
