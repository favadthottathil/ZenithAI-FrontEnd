import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/message.dart';
import '../../theme/app_theme.dart';
import '../bloc/chat_bloc.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final int messageIndex;
  final bool isLast;
  final bool isStreaming;

  const MessageBubble({
    super.key,
    required this.message,
    required this.messageIndex,
    this.isLast = false,
    this.isStreaming = false,
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
    if (widget.isStreaming ||
        (widget.message.role == MessageRole.assistant &&
            widget.message.text.isEmpty)) {
      _cursorController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate =
        widget.isStreaming ||
        (widget.message.role == MessageRole.assistant &&
            widget.message.text.isEmpty);
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

  String _formatText(String text) {
    return text
        .split('\n')
        .map((line) {
          final trimmed = line.trim();

          // Match lines starting with a single asterisk and space like "* Heading"
          final regExpBulletHeader = RegExp(r'^\*\s+(.*)$');
          if (regExpBulletHeader.hasMatch(trimmed)) {
            return trimmed.replaceAllMapped(regExpBulletHeader, (match) {
              final content = match.group(1)?.trim() ?? '';
              var cleanContent = content;
              if (cleanContent.startsWith('**') &&
                  cleanContent.endsWith('**')) {
                cleanContent = cleanContent
                    .substring(2, cleanContent.length - 2)
                    .trim();
              }
              return '\n\n### $cleanContent\n\n';
            });
          }

          // Match bold titles like "**Introduction**" or "**1. Step:**" at the start of a line
          final regExpDouble = RegExp(r'^\*\*([^* \t][^*]*)\*\*([:.]?)(.*)$');
          if (regExpDouble.hasMatch(trimmed)) {
            return trimmed.replaceAllMapped(regExpDouble, (match) {
              final content = match.group(1)?.trim() ?? '';
              final punctuation = match.group(2) ?? '';
              final rest = match.group(3)?.trim() ?? '';

              if (rest.isNotEmpty) {
                return '\n\n### $content$punctuation\n\n$rest\n\n';
              } else {
                return '\n\n### $content$punctuation\n\n';
              }
            });
          }

          // Match titles like "*Introduction*" or "*1. Step:*" at the start of a line
          final regExpSingle = RegExp(r'^\*([^* \t][^*]*)\*([:.]?)(.*)$');
          if (regExpSingle.hasMatch(trimmed)) {
            return trimmed.replaceAllMapped(regExpSingle, (match) {
              final content = match.group(1)?.trim() ?? '';
              final punctuation = match.group(2) ?? '';
              final rest = match.group(3)?.trim() ?? '';

              if (rest.isNotEmpty) {
                return '\n\n### $content$punctuation\n\n$rest\n\n';
              } else {
                return '\n\n### $content$punctuation\n\n';
              }
            });
          }
          return line;
        })
        .join('\n');
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
                child: Container(
                  padding: isUser
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                      : const EdgeInsets.only(top: 4, bottom: 4, right: 16),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF2F2F2F) // Soft ChatGPT charcoal pill
                        : Colors
                              .transparent, // Assistant content flows background-free
                    borderRadius: isUser
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(4),
                          )
                        : null,
                  ),
                  child: (isThinking || isStreaming)
                      // Thinking & streaming: blinking cursor with text flowing in
                      ? _buildStreamingText(message.text)
                      // After streaming complete: full rich Markdown formatting
                      : _buildMarkdownContent(context, message.text),
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
                        SnackBar(
                          content: const Text("Copied response to clipboard"),
                          backgroundColor: AppTheme.surfaceColor,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 1500),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
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
                        SnackBar(
                          content: Text(
                            !message.isSpeaking
                                ? "Reading response aloud..."
                                : "Speech stopped",
                          ),
                          backgroundColor: AppTheme.surfaceColor,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 1500),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text("Regenerating response..."),
                            backgroundColor: AppTheme.surfaceColor,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(milliseconds: 1500),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
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

  // Lightweight streaming text with smooth animated cursor — no markdown parsing overhead
  Widget _buildStreamingText(String text) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 15.5,
              height: 1.6,
              letterSpacing: 0.1,
            ),
          ),
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

  // No longer used — thinking state now shows the same blinking cursor as streaming

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
}

// Custom breathing animation dot for the thinking indicator
class AnimatedDot extends StatefulWidget {
  final int index;
  const AnimatedDot({super.key, required this.index});

  @override
  State<AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          widget.index * 0.2,
          0.6 + (widget.index * 0.2),
          curve: Curves.easeInOut,
        ),
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: ScaleTransition(
        scale: _animation,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AppTheme.primaryColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
