import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/app_state.dart';
import 'screens/onboarding/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
  runApp(const BaatlyApp());
}

class BaatlyApp extends StatelessWidget {
  const BaatlyApp({super.key});

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
        home: const SplashScreen(),
      ),
    );
  }
}
