import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/kit_screen.dart';
import 'screens/run_screen.dart';
import 'state.dart';
import 'theme.dart';

void main() {
  usePathUrlStrategy();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['InstrumentSerif', 'InstrumentSans', 'JetBrainsMono']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });
  runApp(MeetsApp());
}

GoRouter buildRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/run/:id',
          builder: (context, state) => RunScreen(runId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/kit/:id',
          builder: (context, state) => KitScreen(
            kitId: state.pathParameters['id']!,
            handoff: state.extra is KitHandoff ? state.extra as KitHandoff : null,
          ),
        ),
      ],
      errorBuilder: (context, state) => const HomeScreen(),
    );

/// Lets mouse users drag horizontal rails (Flutter web excludes the mouse
/// from drag scrolling by default).
class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();

  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
}

class MeetsApp extends StatelessWidget {
  MeetsApp({super.key, GoRouter? router}) : router = router ?? buildRouter();

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Meets — comps & first fans, powered by Qloo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: kIsWeb ? ThemeMode.light : ThemeMode.system,
      routerConfig: router,
      scrollBehavior: const _DragEverywhere(),
    );
  }
}
