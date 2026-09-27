import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:toastification/toastification.dart';

import '../presentation/common/app_toast.dart';
import '../presentation/routing/app_routes.dart';

/// The app's one way to log, show a toast or an error, and navigate, so none of
/// those is done differently in two places.
class HelperMethods {
  static void printDebug(dynamic message) {
    if (kDebugMode) {
      print(message);
    }
  }

  static void initEasyLoading() {
    EasyLoading.instance
      ..loadingStyle = EasyLoadingStyle.light
      ..maskType = EasyLoadingMaskType.black
      ..backgroundColor = Colors.white
      ..animationStyle = EasyLoadingAnimationStyle.scale
      ..userInteractions = false
      ..indicatorWidget = LoadingAnimationWidget.discreteCircle(
        color: Colors.deepPurple,
        size: 24,
      );
  }

  static void popTilHome(BuildContext context) {
    popTilRoute(context, AppRoutes.home);
  }

  static void popTilRoute(BuildContext context, String routeName) {
    while (Navigator.of(context).canPop() &&
        !(ModalRoute.of(context)!.settings.name == routeName)) {
      Navigator.of(context).pop();
    }
  }

  static void pushOrGoToRoute(
    BuildContext context,
    String routeName, {
    Object? extra,
  }) {
    if (kIsWeb) {
      context.go(routeName, extra: extra);
    } else {
      context.push(routeName, extra: extra);
    }
  }

  /// Drawn by [AppToast] rather than by toastification's own styles, so a
  /// message arrives on the same surface as every other panel in the app.
  static void showToast({
    required String title,
    required String description,
    ToastificationType type = ToastificationType.info,
    bool autoClose = true,
    Duration autoCloseDuration = const Duration(seconds: 3),
    VoidCallback? onTap,
  }) {
    toastification.showCustom(
      autoCloseDuration: autoClose ? autoCloseDuration : null,
      builder: (context, item) => AppToast(
        title: title,
        description: description,
        type: type,
        onClose: () => toastification.dismiss(item),
        onTap: onTap == null
            ? null
            : () {
                toastification.dismiss(item);
                onTap();
              },
      ),
    );
  }

  static void showError({
    required dynamic error,
    bool autoClose = true,
    Duration autoCloseDuration = const Duration(seconds: 3),
  }) {
    showToast(
      title: 'Error',
      description: '$error',
      type: ToastificationType.error,
      autoClose: autoClose,
      autoCloseDuration: autoCloseDuration,
    );
  }

  static void showSuccess({
    required String message,
    bool autoClose = true,
    Duration autoCloseDuration = const Duration(seconds: 3),
  }) {
    showToast(
      title: 'Success',
      description: message,
      type: ToastificationType.success,
      autoClose: autoClose,
      autoCloseDuration: autoCloseDuration,
    );
  }

  static void showNotificationToast({
    required String title,
    required String description,
    ToastificationType type = ToastificationType.info,
    bool autoClose = true,
    VoidCallback? onTap,
  }) {
    // The same card as every other toast. This one was left on
    // toastification's own style, so "Signed out" arrived as a white card.
    showToast(
      title: title,
      description: description,
      type: type,
      autoClose: autoClose,
      onTap: onTap ?? () {},
    );
  }

  static String formatDateTime(DateTime dateTime) {
    final DateFormat formatter = DateFormat('MMMM dd, yyyy • hh:mm a');
    return formatter.format(dateTime);
  }

  static String formatDate(DateTime dateTime) {
    final DateFormat formatter = DateFormat('MMMM dd, yyyy');
    return formatter.format(dateTime);
  }
}
