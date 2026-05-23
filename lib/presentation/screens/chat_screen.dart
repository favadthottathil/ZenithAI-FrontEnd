import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../theme/app_theme.dart';
import '../bloc/chat_bloc.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom({bool smooth = false}) {
    if (_scrollController.hasClients) {
      if (smooth) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      drawer: isDesktop ? null : _buildDrawer(context),
      body: Row(
        children: [
          if (isDesktop) _buildSidebar(context),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(context, isDesktop),
                Expanded(
                  child: BlocConsumer<ChatBloc, ChatState>(
                    listener: (context, state) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(smooth: state is! ChatStreaming));
                    },
                    builder: (context, state) {
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(
                            message: state.messages[index],
                            isLast: index == state.messages.length - 1,
                            isStreaming: state is ChatStreaming && index == state.messages.length - 1,
                            onTextTyped: () {
                              _scrollToBottom(smooth: false);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                ChatInput(
                  onSend: (text) {
                    context.read<ChatBloc>().add(ChatMessageSent(text));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDesktop) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
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
            IconButton(icon: const Icon(LucideIcons.share_2, size: 20), onPressed: () {}),
            IconButton(icon: const Icon(LucideIcons.settings, size: 20), onPressed: () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 260,
      color: AppTheme.backgroundColor.withBlue(20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: _buildNewChatButton(context),
          ),
          const Expanded(child: _HistoryList()),
          _buildUserProfile(),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.backgroundColor,
      child: Column(
        children: [
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildNewChatButton(context),
          ),
          const Expanded(child: _HistoryList()),
          _buildUserProfile(),
        ],
      ),
    );
  }

  Widget _buildNewChatButton(BuildContext context) {
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
        onPressed: () {
          // Add logic to reset chat
        },
      ),
    );
  }

  Widget _buildUserProfile() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black12,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
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
          leading: const Icon(LucideIcons.message_square, size: 18, color: AppTheme.mutedTextColor),
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
