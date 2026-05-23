import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/message.dart';
import '../../theme/app_theme.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isLast;
  final bool isStreaming;
  final VoidCallback? onTextTyped;

  const MessageBubble({
    super.key,
    required this.message,
    this.isLast = false,
    this.isStreaming = false,
    this.onTextTyped,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  String _displayedText = "";
  late AnimationController _cursorController;
  Timer? _typewriterTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isLast && widget.message.role == MessageRole.assistant) {
      _startTypewriter(widget.message.text);
    } else {
      _displayedText = widget.message.text;
    }

    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  void _startTypewriter(String targetText) {
    _typewriterTimer?.cancel();

    // If the text is already caught up, do nothing
    if (_displayedText == targetText) return;

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 20), (
      timer,
    ) {
      if (_displayedText.length < targetText.length) {
        setState(() {
          // Take the next character(s)
          _displayedText = targetText.substring(0, _displayedText.length + 1);
        });
        widget.onTextTyped?.call();
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.message.text != oldWidget.message.text) {
      if (widget.isLast && widget.message.role == MessageRole.assistant) {
        _startTypewriter(widget.message.text);
      } else {
        setState(() {
          _displayedText = widget.message.text;
        });
      }
    }
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  String _formatText(String text) {
    return text
        .split('\n')
        .map((line) {
          final trimmed = line.trim();

          // Match bold titles like "**Introduction**", "**1. Step:**", "**Note.**" on a single line
          final regExpDouble = RegExp(r'^\*\*([^*]+)\*\*([:.]?)$');
          if (regExpDouble.hasMatch(trimmed)) {
            return trimmed.replaceAllMapped(regExpDouble, (match) {
              final content = match.group(1);
              final punctuation = match.group(2) ?? '';
              return '\n### $content$punctuation\n';
            });
          }

          // Match italic/bold-ish titles like "*Introduction*", "*1. Step:*", "*Note.*" on a single line
          final regExpSingle = RegExp(r'^\*([^*]+)\*([:.]?)$');
          if (regExpSingle.hasMatch(trimmed)) {
            return trimmed.replaceAllMapped(regExpSingle, (match) {
              final content = match.group(1);
              final punctuation = match.group(2) ?? '';
              return '\n### $content$punctuation\n';
            });
          }
          return line;
        })
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    bool isUser = widget.message.role == MessageRole.user;
    bool isAssistant = widget.message.role == MessageRole.assistant;
    bool isThinking = isAssistant && widget.message.text.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
              if (!isUser) _buildAvatar(false),
              const SizedBox(width: 12),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppTheme.primaryColor
                        : AppTheme.surfaceColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: isThinking
                      ? _buildThinkingIndicator()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: _formatText(_displayedText),
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(
                                    Theme.of(context),
                                  ).copyWith(
                                    blockSpacing: 26.0,
                                    p: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      height: 1.65,
                                    ),
                                    code: GoogleFonts.firaCode(
                                      backgroundColor: Colors.black26,
                                      color: Colors.pinkAccent,
                                    ),
                                    strong: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    h1: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h2: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h3: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h1Padding: const EdgeInsets.only(
                                      top: 32,
                                      bottom: 16,
                                    ),
                                    h2Padding: const EdgeInsets.only(
                                      top: 28,
                                      bottom: 14,
                                    ),
                                    h3Padding: const EdgeInsets.only(
                                      top: 24,
                                      bottom: 12,
                                    ),
                                    listBullet: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    listBulletPadding: const EdgeInsets.only(
                                      right: 12,
                                      top: 2,
                                    ),
                                    listIndent: 24.0,
                                  ),
                            ),
                            if (widget.isLast &&
                                isAssistant &&
                                (widget.isStreaming ||
                                    _displayedText.length <
                                        widget.message.text.length))
                              _buildStreamingCursor(),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 12),
              if (isUser) _buildAvatar(true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return TweenAnimationBuilder(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 400 + (index * 200)),
          builder: (context, double value, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.3 + (0.7 * (1.0 - value).abs()),
                ),
                shape: BoxShape.circle,
              ),
            );
          },
          onEnd: () {
            // Restart or use a more robust animation
          },
        );
      }),
    );
  }

  Widget _buildStreamingCursor() {
    return FadeTransition(
      opacity: _cursorController,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        width: 8,
        height: 16,
        color: AppTheme.primaryColor.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isUser
              ? [AppTheme.primaryColor, AppTheme.secondaryColor]
              : [Colors.grey[700]!, Colors.grey[800]!],
        ),
      ),
      child: Icon(
        isUser ? Icons.person : Icons.auto_awesome,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}
