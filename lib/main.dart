import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/security/screen_security.dart';
import 'data/repositories/chat_repository_impl.dart';
import 'presentation/bloc/chat_bloc.dart';
import 'presentation/screens/chat_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Apply the saved screen-privacy preference (default ON) before the UI shows.
  await ScreenSecurity.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (context) => ChatRepositoryImpl(),
      child: BlocProvider(
        create: (context) =>
            ChatBloc(repository: context.read<ChatRepositoryImpl>()),
        child: MaterialApp(
          title: 'Zenith AI',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: const ChatScreen(),
        ),
      ),
    );
  }
}
