import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart' as platform;

FileSystem _fileSystem = const LocalFileSystem();

FileSystem get fileSystem => _fileSystem;

@visibleForTesting
set fileSystem(FileSystem value) => _fileSystem = value;

Future<Directory> temporaryDirectory() async =>
    fileSystem.directory((await platform.getTemporaryDirectory()).path);

Future<Directory> applicationCacheDirectory() async =>
    fileSystem.directory((await platform.getApplicationCacheDirectory()).path);

Future<Directory> applicationSupportDirectory() async => fileSystem.directory(
  (await platform.getApplicationSupportDirectory()).path,
);
