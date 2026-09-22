import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'crash_reporting.dart';

final globalScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void installGlobalErrorHandlers() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    if (details.silent) return;
    reportUnhandledError(details.exception, details.stack);
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    previousPlatformOnError?.call(error, stack);
    reportUnhandledError(error, stack);
    return true;
  };
}

void reportZoneError(Object error, StackTrace stack) {
  unawaited(captureCrash(error, stack));
  reportUnhandledError(error, stack);
}

String formatErrorMessage(Object error, StackTrace? stack) {
  return stack == null ? error.toString() : '$error\n\n$stack';
}

String firstLineOf(String message) => message.split('\n').first;

@visibleForTesting
bool showUnhandledErrorSnackBars = kDebugMode;

void reportUnhandledError(Object error, StackTrace? stack) {
  final message = formatErrorMessage(error, stack);
  debugPrint('Unhandled error: $message');
  if (showUnhandledErrorSnackBars) showErrorSnackBar(message);
}

void showErrorSnackBar(String message) {
  scheduleMicrotask(() {
    final messenger = globalScaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(buildErrorSnackBar(message));
  });
}

SnackBar buildErrorSnackBar(String message) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 8),
    persist: false,
    backgroundColor: _errorSnackBarColor,
    content: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            firstLineOf(message),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
    action: SnackBarAction(
      label: 'Copy',
      textColor: Colors.white,
      onPressed: () => Clipboard.setData(ClipboardData(text: message)),
    ),
  );
}

const _errorSnackBarColor = Color(0xFFB3261E);
