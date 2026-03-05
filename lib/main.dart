import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sizer/sizer.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';

import 'logic/cubits/theme/theme_cubit.dart';
import 'logic/helper_methods.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory((await getTemporaryDirectory()).path),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    HelperMethods.initEasyLoading();
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: KeyboardDismisser(
        child: MultiBlocProvider(
          providers: [BlocProvider(create: (_) => ThemeCubit())],
          child: Sizer(
            builder: (context, orientation, screenType) {
              return BlocBuilder<ThemeCubit, ThemeState>(
                builder: (context, themeState) {
                  return MaterialApp.router(
                    routerConfig: AppRoutes.router,
                    darkTheme: AppTheme.darkTheme,
                    theme: AppTheme.lightTheme,
                    themeMode: themeState.themeMode,
                    builder: EasyLoading.init(),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
