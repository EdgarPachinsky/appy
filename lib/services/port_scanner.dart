import 'dart:io';

import 'resource_monitor.dart';

/// A TCP port something is listening on.
class PortInfo {
  const PortInfo({
    required this.port,
    required this.pid,
    required this.command,
    required this.address,
    this.cwd,
  });

  final int port;
  final int pid;
  final String command;

  /// e.g. `*`, `127.0.0.1`, `[::1]`.
  final String address;

  /// Working directory of the process (used to match it to a project).
  final String? cwd;

  bool get isLocalOnly => address.startsWith('127.') || address == '[::1]' || address == 'localhost';
}

class PortScanner {
  static final _devCommand = RegExp(
    r'^(node|nodejs|npm|npx|yarn|pnpm|bun|deno|dart|dartaotruntime|dartvm|flutter|python\d*(\.\d+)?|Python|'
    r'uvicorn|gunicorn|ruby|rails|puma|java|gradle|kotlin|go|air|php|php-fpm|cargo|rustc|dotnet|'
    r'postgres|mysqld|mariadbd|mongod|redis-server|nginx|httpd|caddy|docker|com\.docker.*|vpnkit.*|'
    r'esbuild|vite|webpack|next-server|beam\.smp|elixir|erl|ollama|qemu.*|java.*|.*[Ss]erver)$',
  );

  /// Listening TCP ports of processes the current user can see (and kill).
  static Future<List<PortInfo>> scan() async {
    if (Platform.isWindows) return _scanWindows();
    try {
      final result = await Process.run(
        '/usr/sbin/lsof',
        ['+c', '0', '-nP', '-iTCP', '-sTCP:LISTEN', '-F', 'pcn'],
      ).timeout(const Duration(seconds: 8));

      final found = <String, PortInfo>{};
      int? pid;
      var command = '';
      for (final line in (result.stdout as String).split('\n')) {
        if (line.isEmpty) continue;
        final value = line.substring(1);
        switch (line[0]) {
          case 'p':
            pid = int.tryParse(value);
          case 'c':
            command = value;
          case 'n':
            final colon = value.lastIndexOf(':');
            final port = colon == -1 ? null : int.tryParse(value.substring(colon + 1));
            if (pid == null || port == null) continue;
            final key = '$pid:$port';
            // Same port on IPv4 + IPv6 → keep one row, prefer the wider address.
            final address = value.substring(0, colon);
            final existing = found[key];
            if (existing == null || address == '*') {
              found[key] = PortInfo(port: port, pid: pid, command: command, address: address);
            }
        }
      }

      final cwds = await _cwds(found.values.map((p) => p.pid).toSet());
      final ports = [
        for (final p in found.values)
          PortInfo(port: p.port, pid: p.pid, command: p.command, address: p.address, cwd: cwds[p.pid]),
      ]..sort((a, b) => a.port.compareTo(b.port));
      return ports;
    } catch (_) {
      return const [];
    }
  }

  // shortcut: no cwd on Windows (no cheap way to read another process's), so ports aren't matched to projects by folder.
  static Future<List<PortInfo>> _scanWindows() async {
    try {
      final results = await Future.wait([
        Process.run('netstat', ['-ano']),
        Process.run('tasklist', ['/fo', 'csv', '/nh']),
      ]).timeout(const Duration(seconds: 8));
      return parseNetstat(results[0].stdout as String, parseTasklist(results[1].stdout as String));
    } catch (_) {
      return const [];
    }
  }

  /// Listening TCP rows of `netstat -ano`; [names] is pid → image name from `tasklist`.
  static List<PortInfo> parseNetstat(String out, Map<int, String> names) {
    final found = <String, PortInfo>{};
    for (final line in out.split('\n')) {
      // Proto, local, foreign, state (localized, so unused), pid. Listeners are the TCP rows with foreign port 0.
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length != 5 || !parts[0].startsWith('TCP') || !parts[2].endsWith(':0')) continue;
      final colon = parts[1].lastIndexOf(':');
      final port = int.tryParse(parts[1].substring(colon + 1));
      final pid = int.tryParse(parts[4]);
      if (colon == -1 || port == null || pid == null || pid <= 4) continue; // 0/4 = Idle / System
      final raw = parts[1].substring(0, colon);
      final address = raw == '0.0.0.0' || raw == '[::]' ? '*' : raw;
      final key = '$pid:$port';
      final existing = found[key];
      if (existing == null || address == '*') {
        found[key] = PortInfo(port: port, pid: pid, command: names[pid] ?? '', address: address);
      }
    }
    return found.values.toList()..sort((a, b) => a.port.compareTo(b.port));
  }

  /// pid → name without `.exe`, from `tasklist /fo csv /nh`.
  static Map<int, String> parseTasklist(String out) => {
        for (final m in RegExp(r'^"([^"]*)","(\d+)"', multiLine: true).allMatches(out))
          int.parse(m.group(2)!): m.group(1)!.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), ''),
      };

  /// Dev servers, databases, runtimes — hides AirPlay, Spotify & friends.
  static bool looksLikeDev(PortInfo p) => _devCommand.hasMatch(p.command);

  static Future<Map<int, String>> _cwds(Set<int> pids) async {
    if (pids.isEmpty) return const {};
    try {
      final result = await Process.run(
        '/usr/sbin/lsof',
        ['-a', '-p', pids.join(','), '-d', 'cwd', '-Fn'],
      ).timeout(const Duration(seconds: 5));
      final out = <int, String>{};
      int? pid;
      for (final line in (result.stdout as String).split('\n')) {
        if (line.isEmpty) continue;
        if (line[0] == 'p') pid = int.tryParse(line.substring(1));
        if (line[0] == 'n' && pid != null) out[pid] = line.substring(1);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// pid → parent pid for every process.
  static Future<Map<int, int>> parents() async {
    try {
      if (Platform.isWindows) return {for (final p in await windowsProcesses()) p.pid: p.ppid};
      final result = await Process.run('/bin/ps', ['-A', '-o', 'pid=,ppid=']);
      final out = <int, int>{};
      for (final line in (result.stdout as String).split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final pid = int.tryParse(parts[0]), ppid = int.tryParse(parts[1]);
        if (pid != null && ppid != null) out[pid] = ppid;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  static bool isAlive(int pid) {
    try {
      if (Platform.isWindows) {
        final out = Process.runSync('tasklist', ['/fi', 'PID eq $pid', '/fo', 'csv', '/nh']).stdout as String;
        return parseTasklist(out).containsKey(pid);
      }
      return Process.runSync('/bin/kill', ['-0', '$pid']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
