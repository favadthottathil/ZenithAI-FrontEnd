import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      text: "Hello! I'm your AI assistant. How can I help you today?",
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
    ),
  ];

  void _addMessage(String text) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          role: MessageRole.user,
          timestamp: DateTime.now(),
        ),
      );
    });

    // Simulate LLM response
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                "This is a simulated AI response. Currently, I'm just a UI prototype, but I'm ready to be connected to a real LLM for streaming chat!",
            role: MessageRole.assistant,
            timestamp: DateTime.now(),
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      drawer: isDesktop ? null : _buildDrawer(),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(isDesktop),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
                ),
                ChatInput(onSend: _addMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(LucideIcons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          const SizedBox(width: 8),
          const Text(
            "AI Chatbot",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.share_2, size: 20),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings, size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: AppTheme.backgroundColor.withBlue(20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: _buildNewChatButton(),
          ),
          const Expanded(child: _HistoryList()),
          _buildUserProfile(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppTheme.backgroundColor,
      child: Column(
        children: [
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildNewChatButton(),
          ),
          const Expanded(child: _HistoryList()),
          _buildUserProfile(),
        ],
      ),
    );
  }

  Widget _buildNewChatButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text("New Chat"),
        onPressed: () {},
      ),
    );
  }

  Widget _buildUserProfile() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black12,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppTheme.primaryColor,
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "User Account",
              style: TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.ellipsis, size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: 5,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const Icon(
            LucideIcons.message_square,
            size: 18,
            color: AppTheme.mutedTextColor,
          ),
          title: Text(
            "Previous Chat ${index + 1}",
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () {},
        );
      },
    );
  }
}
