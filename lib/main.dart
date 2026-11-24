import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/api.dart';
import 'data/app_state.dart';
import 'screens/home/home_shell.dart';
import 'screens/onboarding/splash_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  await AppState.instance.load();
  await Api.instance.load();
  runApp(BaatlyApp(skipOnboarding: AppState.instance.onboarded));
}

class BaatlyApp extends StatelessWidget {
  /// Decided once at launch, so finishing onboarding doesn't swap the root route.
  final bool skipOnboarding;
  const BaatlyApp({super.key, this.skipOnboarding = false});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'BAATLY',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: state.themeMode,
        builder: (context, child) {
          // Respect the user's "reduce motion" preference everywhere.
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(disableAnimations: mq.disableAnimations || state.reduceMotion),
            child: child!,
          );
        },
        // Animated splash + onboarding only on first launch; afterwards straight to chats.
        home: skipOnboarding ? const HomeShell() : const SplashScreen(),
      ),
    );
  }
}
