import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import '../../domain/models/message.dart';
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
  final TextEditingController _searchController = TextEditingController();
  bool _showSidebar = true;

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return false;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) <= 120;
  }

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
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: isDesktop ? null : _buildDrawer(context),
      body: Row(
        children: [
          if (isDesktop && _showSidebar) _buildSidebar(context),
          Expanded(
            child: Column(
              children: [
                _buildAppBar(context, isDesktop),
                Expanded(
                  child: BlocConsumer<ChatBloc, ChatState>(
                    listener: (context, state) {
                      if (state is ChatStreaming) {
                        final isJustStarted =
                            state.messages.isNotEmpty &&
                            state.messages.last.role == MessageRole.assistant &&
                            state.messages.last.text.isEmpty;
                        if (isJustStarted || _isNearBottom()) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _scrollToBottom(smooth: isJustStarted),
                          );
                        }
                      } else {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _scrollToBottom(smooth: true),
                        );
                      }
                    },
                    builder: (context, state) {
                      if (state.messages.isEmpty) {
                        return _buildEmptyState(context);
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(
                            messageIndex: index,
                            message: state.messages[index],
                            isLast: index == state.messages.length - 1,
                            isStreaming:
                                state is ChatStreaming &&
                                index == state.messages.length - 1,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.backgroundColor,
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
          ),
        ),
        child: Row(
          children: [
            if (!isDesktop || !_showSidebar)
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(LucideIcons.menu, size: 20),
                  onPressed: () {
                    if (!isDesktop) {
                      Scaffold.of(context).openDrawer();
                    } else {
                      setState(() {
                        _showSidebar = true;
                      });
                    }
                  },
                ),
              ),
            const SizedBox(width: 8),
            const Text(
              "Zenith AI",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            // New chat compose icon (ChatGPT style)
            IconButton(
              icon: Icon(
                LucideIcons.square_pen,
                size: 20,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              onPressed: () {
                context.read<ChatBloc>().add(const CreateNewConversation());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final suggestions = [
      {
        "title": "Plan a trip",
        "subtitle": "to explore historical sights in Rome",
      },
      {"title": "Help me study", "subtitle": "vocabulary for a language test"},
      {
        "title": "Write a thank you note",
        "subtitle": "to a coworker who went above and beyond",
      },
      {
        "title": "Brainstorm ideas",
        "subtitle": "for a fun team building event at work",
      },
    ];

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Zenith AI Logo Image Loader
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: Image.asset(
                    'assets/images/zenith_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          LucideIcons.sparkles,
                          color: AppTheme.primaryColor,
                          size: 24,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "How can I help you today?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              // Grid suggestion cards
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final s = suggestions[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    color: const Color(0xFF212121),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        final promptText = "${s['title']} ${s['subtitle']}";
                        context.read<ChatBloc>().add(
                          ChatMessageSent(promptText),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              s['title']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: Text(
                                s['subtitle']!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.03)),
        ),
      ),
      child: Column(
        children: [
          // Sidebar Header with collapse action
          Padding(
            padding: const EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Conversations",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    LucideIcons.chevron_left,
                    size: 18,
                    color: Colors.white54,
                  ),
                  onPressed: () {
                    setState(() {
                      _showSidebar = false;
                    });
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: _buildNewChatButton(context),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: _buildSearchBox(),
          ),
          Expanded(
            child: _HistoryList(
              onConversationSelected: () {
                setState(() {
                  _showSidebar = false;
                });
              },
            ),
          ),
          const SizedBox(
            height: 16,
          ), // Clean spacer instead of profile/upgrade actions
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF171717),
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _buildNewChatButton(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: _buildSearchBox(),
          ),
          const Expanded(child: _HistoryList()),
          const SizedBox(
            height: 16,
          ), // Clean spacer instead of profile/upgrade actions
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            size: 14,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Search conversations...",
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewChatButton(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              alignment: Alignment.centerLeft,
              foregroundColor: Colors.white.withValues(alpha: 0.9),
            ),
            icon: const Icon(
              LucideIcons.plus,
              size: 16,
              color: AppTheme.primaryColor,
            ),
            label: const Text(
              "New Chat",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              buttonContext.read<ChatBloc>().add(const CreateNewConversation());
              if (Scaffold.of(buttonContext).isDrawerOpen) {
                Navigator.of(buttonContext).pop();
              } else {
                setState(() {
                  _showSidebar = false;
                });
              }
            },
          ),
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  final VoidCallback? onConversationSelected;
  const _HistoryList({this.onConversationSelected});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        final conversations = state.conversations;

        if (conversations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "No past chats yet",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final convo = conversations[index];
            final title = convo["title"] ?? "New Chat";
            final conversationId = convo["conversation_id"];
            final isActive = state.conversationId == conversationId;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ListTile(
                dense: true,
                selected: isActive,
                selectedTileColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                leading: Icon(
                  LucideIcons.message_square,
                  size: 16,
                  color: isActive
                      ? AppTheme.primaryColor
                      : Colors.white.withValues(alpha: 0.4),
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(
                    LucideIcons.trash_2,
                    size: 14,
                    color: Colors.redAccent,
                  ),
                  onPressed: () {
                    context.read<ChatBloc>().add(
                      DeleteConversation(conversationId),
                    );
                  },
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {
                  context.read<ChatBloc>().add(
                    SelectConversation(conversationId),
                  );
                  if (Scaffold.of(context).isDrawerOpen) {
                    Navigator.of(context).pop();
                  }
                  if (onConversationSelected != null) {
                    onConversationSelected!();
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
