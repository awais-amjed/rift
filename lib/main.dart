// The original content is temporarily commented out to allow generating a self-contained demo - feel free to uncomment later.

// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_easyloading/flutter_easyloading.dart';
// import 'package:hydrated_bloc/hydrated_bloc.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:toastification/toastification.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:sizer/sizer.dart';
// import 'package:keyboard_dismisser/keyboard_dismisser.dart';
// import 'package:tray_manager/tray_manager.dart';
// import 'package:window_manager/window_manager.dart';
//
// import 'data/repositories/server_repository.dart';
// import 'logic/cubits/app/app_cubit.dart';
// import 'logic/cubits/livekit/livekit_cubit.dart';
// import 'logic/cubits/server/server_cubit.dart';
// import 'logic/cubits/theme/theme_cubit.dart';
// import 'logic/helper_methods.dart';
// import 'presentation/routing/app_routes.dart';
// import 'presentation/theme/app_theme.dart';
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   HydratedBloc.storage = await HydratedStorage.build(
//     storageDirectory: kIsWeb
//         ? HydratedStorageDirectory.web
//         : HydratedStorageDirectory((await getTemporaryDirectory()).path),
//   );
//
//   if (!kIsWeb) {
//     await windowManager.ensureInitialized();
//     windowManager.waitUntilReadyToShow(
//       const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
//     );
//
//     await trayManager.setIcon('assets/images/tray_icon.png');
//     await trayManager.setContextMenu(
//       Menu(
//         items: [
//           MenuItem(key: 'show', label: 'Show Rift'),
//           MenuItem.separator(),
//           MenuItem(key: 'quit', label: 'Quit'),
//         ],
//       ),
//     );
//   }
//
//   runApp(const MyApp());
// }
//
// class MyApp extends StatefulWidget {
//   const MyApp({super.key});
//
//   @override
//   State<MyApp> createState() => _MyAppState();
// }
//
// class _MyAppState extends State<MyApp> {
//   @override
//   void initState() {
//     super.initState();
//
//     HelperMethods.initEasyLoading();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return ToastificationWrapper(
//       child: KeyboardDismisser(
//         child: MultiBlocProvider(
//           providers: [
//             BlocProvider(create: (_) => ThemeCubit()),
//             BlocProvider(create: (_) => ServerCubit()),
//             BlocProvider(create: (_) => AppCubit()),
//             BlocProvider(
//               create: (context) => LiveKitCubit(
//                 repository: ServerRepository(),
//                 appCubit: context.read<AppCubit>(),
//               ),
//             ),
//           ],
//           child: Sizer(
//             builder: (context, orientation, screenType) {
//               return BlocBuilder<ThemeCubit, ThemeState>(
//                 builder: (context, themeState) {
//                   return MaterialApp.router(
//                     routerConfig: AppRoutes.router,
//                     darkTheme: AppTheme.darkTheme,
//                     theme: AppTheme.lightTheme,
//                     themeMode: themeState.themeMode,
//                     builder: EasyLoading.init(),
//                   );
//                 },
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }
// }
//

import 'package:flutter/material.dart';
import 'package:rift/src/rust/api/simple.dart';
import 'package:rift/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_rust_bridge quickstart')),
        body: Center(
          child: Text(
            'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`',
          ),
        ),
      ),
    );
  }
}
