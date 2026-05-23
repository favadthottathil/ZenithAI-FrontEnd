import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSend;

  const ChatInput({super.key, required this.onSend});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (val) => print('SPEECH ERROR: $val'),
        onStatus: (val) => print('SPEECH STATUS: $val'),
      );
      setState(() {});
    } catch (e) {
      print('SPEECH INIT EXCEPTION: $e');
    }
  }

  void _toggleListening() async {
    if (!_isListening) {
      if (!_speechEnabled) {
        _speechEnabled = await _speechToText.initialize(
          onError: (val) => print('SPEECH ERROR: $val'),
          onStatus: (val) => print('SPEECH STATUS: $val'),
        );
      }
      
      if (_speechEnabled) {
        setState(() {
          _isListening = true;
        });
        
        await _speechToText.listen(
          onResult: (result) {
            setState(() {
              _controller.text = result.recognizedWords;
            });
          },
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speech recognition is not available on this device.')),
          );
        }
      }
    } else {
      await _speechToText.stop();
      setState(() {
        _isListening = false;
      });
    }
  }

  void _handleSend() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSend(_controller.text.trim());
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(LucideIcons.paperclip, color: AppTheme.mutedTextColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 1,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _isListening ? "Listening..." : "Ask anything...",
                    hintStyle: TextStyle(
                      color: _isListening ? AppTheme.primaryColor : AppTheme.mutedTextColor,
                      fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.mic,
                  color: _isListening ? AppTheme.primaryColor : AppTheme.mutedTextColor,
                  size: 20,
                ),
                onPressed: _toggleListening,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(LucideIcons.send, size: 20),
                  onPressed: _handleSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
