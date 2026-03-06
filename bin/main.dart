/// Java language support plugin for Lumide IDE.
///
/// Registers Eclipse JDT Language Server for Java files.
/// Auto-detects JDK and downloads JDTLS if not present.
/// Supports multiple JDTLS versions side-by-side depending on the active JDK.
library;

import 'dart:convert';
import 'dart:io';

import 'package:lumide_api/lumide_api.dart';

void main() => JavaPlugin().run();

class JavaPlugin extends LumidePlugin {
  static const _logPrefix = '☕';
  static const _pluginName = 'Java';
  static const _pluginId = 'java-lsp';
  static const _languageId = 'java';
  static const _fileExtensions = ['.java'];
  static const _defaultLspCommand = 'java';
  static const _minJavaVersion = 17;

  static const _restartCommandId = 'lumide_java.restartLsp';
  static const _reinstallCommandId = 'lumide_java.reinstallJdtls';
  static const _upgradeCommandId = 'lumide_java.upgradeJdtls';

  /// Base path for all JDTLS installations for this plugin.
  String get _jdtlsBaseDir => '$_homeDir/.sofluffy/lumide/lsp/lumide_java';

  String _jdtlsDir(String version) => '$_jdtlsBaseDir/jdtls-$version';

  late String _homeDir;
  String? _activeVersion;
  String _lspCommand = _defaultLspCommand;

  @override
  Future<void> onActivate(LumideContext context) async {
    log('$_logPrefix $_pluginName plugin activated');

    // Load custom Java Home from settings if available
    final customJavaHome = await context.workspace
        .getConfiguration('$_pluginId.javaHome') as String?;
    final javaHome =
        customJavaHome?.trim() ?? Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.trim().isNotEmpty) {
      final javaBin = Platform.isWindows ? 'java.exe' : 'java';
      _lspCommand = '$javaHome/bin/$javaBin';
    }

    // Resolve home directory
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    _homeDir = home ?? '';

    // 1. Check if JDK is available
    final javaCheck = await context.shell.run(_lspCommand, ['-version']);
    if (javaCheck.exitCode != 0) {
      await context.window.showMessage(
        '$_pluginName is not installed. Please install a JDK ($_minJavaVersion+) to enable $_pluginName support.\n\n'
        'Recommended: https://adoptium.net',
        title: _pluginName,
        type: MessageType.warning,
      );
      log('$_logPrefix JDK not found, aborting');
      return;
    }

    final javaOutput =
        (javaCheck.stdout.toString() + javaCheck.stderr.toString()).trim();
    final javaVersionMatch = RegExp(r'version "(\d+)"').firstMatch(javaOutput);
    final majorVersion = javaVersionMatch != null
        ? int.tryParse(javaVersionMatch.group(1)!)
        : null;

    log('$_logPrefix Found JDK: ${javaOutput.split('\n').first}');

    if (majorVersion != null && majorVersion < _minJavaVersion) {
      await context.window.showMessage(
        'JDTLS requires $_pluginName $_minJavaVersion or newer. You are running $_pluginName $majorVersion.\n\n'
        'Please upgrade your JDK to use $_pluginName features.',
        title: _pluginName,
        type: MessageType.error,
      );
      log('$_logPrefix JDK version $majorVersion too old for JDTLS');
      return;
    }

    final activeMajorVersion = majorVersion ?? _minJavaVersion;

    // 2. Determine target JDTLS version
    final targetVersion =
        await _determineTargetVersion(context, activeMajorVersion);
    if (targetVersion == null) return;
    _activeVersion = targetVersion;

    // 3. Check if JDTLS is already installed
    final jdtlsExists = await _isJdtlsInstalled(context, targetVersion);
    if (!jdtlsExists) {
      final install = await context.window.showConfirmDialog(
        'Eclipse JDT Language Server (v$targetVersion) is required for your $_pluginName version.\n\n'
        'Download it now?',
        title: _pluginName,
      );

      if (!install) {
        log('$_logPrefix User declined JDTLS installation');
        return;
      }

      final success =
          await _downloadJdtls(context, targetVersion, activeMajorVersion);
      if (!success) return;
    }

    // 4. Resolve the launcher jar path
    final launcherJar = await _findLauncherJar(context, targetVersion);
    if (launcherJar == null) {
      await context.window.showMessage(
        'Could not find JDTLS launcher jar. Try reinstalling via '
        '"$_pluginName: Reinstall Language Server".',
        title: _pluginName,
        type: MessageType.error,
      );
      return;
    }

    // 5. Determine config directory based on platform
    final configDir = await _getConfigDir(context, targetVersion);

    // 6. Register the language server
    await _startLsp(context, targetVersion, launcherJar, configDir);

    // 7. Register commands
    _registerCommands(context, activeMajorVersion);

    log('$_logPrefix JDTLS (v$targetVersion) registered for $_languageId files');
  }

  Future<void> _startLsp(
    LumideContext context,
    String version,
    String launcherJar,
    String configDir,
  ) async {
    await context.languages.registerLanguageServer(
      id: _pluginId,
      languageId: _languageId,
      fileExtensions: _fileExtensions,
      command: _lspCommand,
      args: [
        '--add-modules=ALL-SYSTEM',
        '--add-opens',
        'java.base/java.util=ALL-UNNAMED',
        '--add-opens',
        'java.base/java.lang=ALL-UNNAMED',
        '-Declipse.application=org.eclipse.jdt.ls.core.id1',
        '-Dosgi.bundles.defaultStartLevel=4',
        '-Declipse.product=org.eclipse.jdt.ls.core.product',
        '-Xms256m',
        '-Xmx1024m',
        '-jar',
        launcherJar,
        '-configuration',
        configDir,
        '-data',
        '${_jdtlsDir(version)}/workspace',
      ],
    );
  }

  void _registerCommands(LumideContext context, int majorVersion) {
    context.commands.registerCommand(
      id: _restartCommandId,
      title: '$_pluginName: Restart Language Server',
      category: _pluginName,
      callback: ([args]) async {
        if (_activeVersion == null) return;
        final jar = await _findLauncherJar(context, _activeVersion!);
        if (jar == null) return;
        final config = await _getConfigDir(context, _activeVersion!);
        await _startLsp(context, _activeVersion!, jar, config);
        await context.window.showMessage(
          '$_pluginName language server restarted',
          title: _pluginName,
        );
      },
    );

    context.commands.registerCommand(
      id: _reinstallCommandId,
      title: '$_pluginName: Reinstall Active Language Server',
      category: _pluginName,
      callback: ([args]) async {
        if (_activeVersion == null) return;
        await Directory(_jdtlsDir(_activeVersion!)).delete(recursive: true);
        final success =
            await _downloadJdtls(context, _activeVersion!, majorVersion);
        if (success) {
          await context.window.showMessage(
            'JDTLS reinstalled. Restart the language server to apply.',
            title: _pluginName,
          );
        }
      },
    );

    context.commands.registerCommand(
      id: _upgradeCommandId,
      title: '$_pluginName: Upgrade Language Server',
      category: _pluginName,
      callback: ([args]) async {
        if (majorVersion < 21) {
          await context.window.showMessage(
            'Cannot upgrade. $_pluginName 17-20 requires JDTLS 1.38.0.\nTo use a newer JDTLS, upgrade your JDK to 21+.',
            title: _pluginName,
            type: MessageType.warning,
          );
          return;
        }

        final latest = await _fetchLatestVersionFromGithub(context);
        if (latest == null) return;

        if (_activeVersion == latest &&
            await _isJdtlsInstalled(context, latest)) {
          await context.window.showMessage(
            'You are already on the latest JDTLS version (v$latest).',
            title: _pluginName,
          );
          return;
        }

        final success = await _downloadJdtls(context, latest, majorVersion);
        if (success) {
          _activeVersion = latest;
          final jar = await _findLauncherJar(context, latest);
          if (jar != null) {
            final config = await _getConfigDir(context, latest);
            await _startLsp(context, latest, jar, config);
            await context.window.showMessage(
              'JDTLS upgraded to v$latest and restarted.',
              title: _pluginName,
            );
          }
        }
      },
    );
  }

  @override
  Future<void> onDeactivate() async {
    log('$_logPrefix $_pluginName plugin deactivated');
  }

  /// Determines the target JDTLS version to use based on the active JDK.
  Future<String?> _determineTargetVersion(
      LumideContext context, int javaMajorVersion) async {
    if (javaMajorVersion < 21) {
      log('$_logPrefix $_pluginName $javaMajorVersion detected. Targeting JDTLS 1.38.0...');
      return '1.38.0';
    }

    // Java 21+: Find highest installed version, or fetch latest
    final installedVersions = await _getInstalledVersions(context);
    if (installedVersions.isNotEmpty) {
      // Very naive string sort for semver (assumes major.minor.patch)
      // JDTLS versions are usually 1.xx.0
      installedVersions.sort((a, b) {
        final partsA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        final partsB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
        for (var i = 0; i < 3; i++) {
          final pA = i < partsA.length ? partsA[i] : 0;
          final pB = i < partsB.length ? partsB[i] : 0;
          if (pA != pB) return pA.compareTo(pB);
        }
        return 0;
      });
      final highest = installedVersions.last;
      log('$_logPrefix $_pluginName 21+ detected. Using highest installed JDTLS version: $highest...');
      return highest;
    }

    log('$_logPrefix $_pluginName 21+ detected but no JDTLS installed. Fetching latest version...');
    return await _fetchLatestVersionFromGithub(context);
  }

  /// Gets a list of installed JDTLS versions from the base dir.
  Future<List<String>> _getInstalledVersions(LumideContext context) async {
    final baseDir = Directory(_jdtlsBaseDir);
    if (!await baseDir.exists()) return [];

    final versions = <String>[];
    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        final name = entity.uri.pathSegments
            .lastWhere((s) => s.isNotEmpty, orElse: () => '');
        if (name.startsWith('jdtls-')) {
          versions.add(name.substring('jdtls-'.length));
        }
      }
    }
    return versions;
  }

  Future<String?> _fetchLatestVersionFromGithub(LumideContext context) async {
    try {
      final response = await context.http.get(
        'https://api.github.com/repos/eclipse-jdtls/eclipse.jdt.ls/tags?per_page=1',
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode != 200) {
        throw Exception('GitHub API returned ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) {
        throw Exception('No tags found');
      }
      final tag = (data.first as Map<String, dynamic>)['name'] as String;
      return tag.startsWith('v') ? tag.substring(1) : tag;
    } catch (e) {
      log('$_logPrefix Failed to fetch latest version: $e');
      await context.window.showMessage(
        'Failed to fetch latest JDTLS version from GitHub.\n\n$e',
        title: _pluginName,
        type: MessageType.error,
      );
      return null;
    }
  }

  Future<bool> _isJdtlsInstalled(LumideContext context, String version) async {
    final jar = await _findLauncherJar(context, version);
    return jar != null;
  }

  Future<String?> _findLauncherJar(
      LumideContext context, String version) async {
    final pluginDir = Directory('${_jdtlsDir(version)}/plugins');
    if (!await pluginDir.exists()) return null;

    await for (final entity in pluginDir.list()) {
      if (entity is File) {
        final name = entity.uri.pathSegments
            .lastWhere((s) => s.isNotEmpty, orElse: () => '');
        if (name.startsWith('org.eclipse.equinox.launcher_') &&
            name.endsWith('.jar')) {
          return entity.path;
        }
      }
    }
    return null;
  }

  Future<String> _getConfigDir(LumideContext context, String version) async {
    final configName = Platform.isMacOS
        ? 'config_mac'
        : Platform.isWindows
            ? 'config_win'
            : 'config_linux';
    return '${_jdtlsDir(version)}/$configName';
  }

  Future<bool> _downloadJdtls(
    LumideContext context,
    String version,
    int javaMajorVersion,
  ) async {
    final String tarballName;

    try {
      final response = await context.http.get(
        'https://download.eclipse.org/jdtls/milestones/$version/latest.txt',
      );
      if (response.statusCode != 200) {
        throw Exception('latest.txt returned ${response.statusCode}');
      }
      tarballName = response.body.trim();
    } catch (e) {
      log('$_logPrefix Failed to fetch latest.txt: $e');
      await context.window.showMessage(
        'Failed to get JDTLS download info for v$version.\n\n$e',
        title: _pluginName,
        type: MessageType.error,
      );
      return false;
    }

    log('$_logPrefix Downloading $tarballName via IDE downloader...');

    final destDir = Directory(_jdtlsDir(version));
    try {
      await destDir.create(recursive: true);
    } catch (e) {
      await context.window.showMessage(
        'Failed to create directory: ${destDir.path}\n\n$e',
        title: _pluginName,
        type: MessageType.error,
      );
      return false;
    }

    final downloadUrl = 'https://www.eclipse.org/downloads/download.php'
        '?file=/jdtls/milestones/$version/$tarballName'
        '&protocol=https';

    try {
      await context.fs.downloadFile(
        downloadUrl,
        '$destDir/$tarballName',
        label: 'JDTLS v$version',
        extract: true,
      );
    } catch (e) {
      log('$_logPrefix Download failed: $e');
      await context.window.showMessage(
        'Failed to download JDTLS v$version.\n\n$e',
        title: _pluginName,
        type: MessageType.error,
      );
      return false;
    }

    final installed = await _isJdtlsInstalled(context, version);
    if (!installed) {
      log('$_logPrefix Download completed but launcher jar not found');
      await context.window.showMessage(
        'JDTLS download succeeded, but missing launcher jar. Check extraction.',
        title: _pluginName,
        type: MessageType.error,
      );
      return false;
    }

    log('$_logPrefix JDTLS v$version installed to ${destDir.path}');
    return true;
  }
}
