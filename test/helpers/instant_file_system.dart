import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

class InstantFileSystem extends FileSystem {
  const InstantFileSystem();

  @override
  Directory directory(dynamic path) =>
      _InstantDirectory(this, io.Directory(getPath(path)));

  @override
  File file(dynamic path) => _InstantFile(this, io.File(getPath(path)));

  @override
  Link link(dynamic path) => _InstantLink(this, io.Link(getPath(path)));

  @override
  p.Context get path => p.Context();

  @override
  Directory get systemTempDirectory => directory(io.Directory.systemTemp);

  @override
  Directory get currentDirectory => directory(io.Directory.current);

  @override
  set currentDirectory(dynamic path) => io.Directory.current = path;

  @override
  Future<FileStat> stat(String path) => Future.sync(() => statSync(path));

  @override
  FileStat statSync(String path) => io.FileStat.statSync(path);

  @override
  Future<bool> identical(String path1, String path2) =>
      Future.sync(() => identicalSync(path1, path2));

  @override
  bool identicalSync(String path1, String path2) =>
      io.FileSystemEntity.identicalSync(path1, path2);

  @override
  bool get isWatchSupported => false;

  @override
  Future<FileSystemEntityType> type(String path, {bool followLinks = true}) =>
      Future.sync(() => typeSync(path, followLinks: followLinks));

  @override
  FileSystemEntityType typeSync(String path, {bool followLinks = true}) =>
      io.FileSystemEntity.typeSync(path, followLinks: followLinks);
}

Never _waitsOnTheDisk(String api) => throw UnsupportedError(
  'InstantFileSystem has no $api: it would wait on the real disk.',
);

abstract class _InstantEntity<
  T extends FileSystemEntity,
  D extends io.FileSystemEntity
>
    extends ForwardingFileSystemEntity<T, D> {
  _InstantEntity(this.fileSystem, this.delegate);

  @override
  final InstantFileSystem fileSystem;

  @override
  final D delegate;

  @override
  Directory wrapDirectory(io.Directory delegate) =>
      _InstantDirectory(fileSystem, delegate);

  @override
  File wrapFile(io.File delegate) => _InstantFile(fileSystem, delegate);

  @override
  Link wrapLink(io.Link delegate) => _InstantLink(fileSystem, delegate);

  @override
  Future<bool> exists() => Future.sync(existsSync);

  @override
  Future<T> rename(String newPath) => Future.sync(() => renameSync(newPath));

  @override
  Future<String> resolveSymbolicLinks() =>
      Future.sync(resolveSymbolicLinksSync);

  @override
  Future<FileStat> stat() => Future.sync(statSync);

  @override
  Future<T> delete({bool recursive = false}) => Future.sync(() {
    deleteSync(recursive: recursive);
    return this as T;
  });

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _waitsOnTheDisk('watch');
}

class _InstantFile extends _InstantEntity<File, io.File> with ForwardingFile {
  _InstantFile(super.fileSystem, super.delegate);

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      Future.sync(() {
        delegate.createSync(recursive: recursive, exclusive: exclusive);
        return this;
      });

  @override
  Future<File> copy(String newPath) => Future.sync(() => copySync(newPath));

  @override
  Future<int> length() => Future.sync(lengthSync);

  @override
  Future<DateTime> lastAccessed() => Future.sync(lastAccessedSync);

  @override
  Future<dynamic> setLastAccessed(DateTime time) =>
      Future.sync(() => setLastAccessedSync(time));

  @override
  Future<DateTime> lastModified() => Future.sync(lastModifiedSync);

  @override
  Future<dynamic> setLastModified(DateTime time) =>
      Future.sync(() => setLastModifiedSync(time));

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _waitsOnTheDisk('open');

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    try {
      final bytes = readAsBytesSync();
      final to = end == null ? bytes.length : min(end, bytes.length);
      return Stream.value(Uint8List.sublistView(bytes, start ?? 0, to));
    } catch (error, stack) {
      return Stream.error(error, stack);
    }
  }

  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => _waitsOnTheDisk('openWrite');

  @override
  Future<Uint8List> readAsBytes() => Future.sync(readAsBytesSync);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      Future.sync(() => readAsStringSync(encoding: encoding));

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      Future.sync(() => readAsLinesSync(encoding: encoding));

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => Future.sync(() {
    writeAsBytesSync(bytes, mode: mode, flush: flush);
    return this;
  });

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => Future.sync(() {
    writeAsStringSync(contents, mode: mode, encoding: encoding, flush: flush);
    return this;
  });
}

class _InstantDirectory extends _InstantEntity<Directory, io.Directory>
    with ForwardingDirectory<Directory> {
  _InstantDirectory(super.fileSystem, super.delegate);

  @override
  Directory childDirectory(String basename) =>
      fileSystem.directory(fileSystem.path.join(path, basename));

  @override
  File childFile(String basename) =>
      fileSystem.file(fileSystem.path.join(path, basename));

  @override
  Link childLink(String basename) =>
      fileSystem.link(fileSystem.path.join(path, basename));

  @override
  Future<Directory> create({bool recursive = false}) => Future.sync(() {
    createSync(recursive: recursive);
    return this;
  });

  @override
  Future<Directory> createTemp([String? prefix]) =>
      Future.sync(() => createTempSync(prefix));

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    try {
      return Stream.fromIterable(
        listSync(recursive: recursive, followLinks: followLinks),
      );
    } catch (error, stack) {
      return Stream.error(error, stack);
    }
  }
}

class _InstantLink extends _InstantEntity<Link, io.Link> with ForwardingLink {
  _InstantLink(super.fileSystem, super.delegate);

  @override
  Future<Link> create(String target, {bool recursive = false}) =>
      Future.sync(() {
        createSync(target, recursive: recursive);
        return this;
      });

  @override
  Future<Link> update(String target) => Future.sync(() {
    updateSync(target);
    return this;
  });

  @override
  Future<String> target() => Future.sync(targetSync);
}
