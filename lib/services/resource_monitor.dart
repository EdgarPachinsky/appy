import 'dart:io';

/// CPU / memory of a process tree.
class ProcStats {
  const ProcStats({required this.cpu, required this.memoryKb});

  /// Percent of one core (can exceed 100 on multi-core work), like Activity Monitor.
  final double cpu;
  final int memoryKb;

  ProcStats operator +(ProcStats other) => ProcStats(cpu: cpu + other.cpu, memoryKb: memoryKb + other.memoryKb);

  String get cpuLabel => '${cpu.round()}%';

  String get memoryLabel {
    final mb = memoryKb / 1024;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.round()} MB';
  }

  String get label => '$cpuLabel · $memoryLabel';
}

/// Samples `ps` and sums CPU / RSS over each root pid's whole process tree
/// (npm → node → vite, flutter → dart → your app…).
class ResourceMonitor {
  static Map<int, int> _lastCpuTime = const {};
  static DateTime? _lastAt;

  static Future<Map<int, ProcStats>> sample(Iterable<int> rootPids) async {
    final roots = rootPids.toSet();
    if (roots.isEmpty) return const {};
    try {
      final children = <int, List<int>>{};
      final own = <int, ProcStats>{};
      if (Platform.isWindows) {
        // Windows only reports total CPU time, so % comes from the change since the last sample.
        final now = DateTime.now();
        final elapsed100ns = _lastAt == null ? 0 : now.difference(_lastAt!).inMicroseconds * 10;
        final procs = await windowsProcesses();
        for (final p in procs) {
          final before = _lastCpuTime[p.pid];
          final cpu = elapsed100ns > 0 && before != null ? (p.cpuTime - before) * 100 / elapsed100ns : 0.0;
          own[p.pid] = ProcStats(cpu: cpu < 0 ? 0 : cpu, memoryKb: p.memoryBytes ~/ 1024);
          children.putIfAbsent(p.ppid, () => []).add(p.pid);
        }
        _lastCpuTime = {for (final p in procs) p.pid: p.cpuTime};
        _lastAt = now;
      } else {
        final result = await Process.run('/bin/ps', ['-A', '-o', 'pid=,ppid=,%cpu=,rss=']);
        for (final line in (result.stdout as String).split('\n')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length < 4) continue;
          final pid = int.tryParse(parts[0]);
          final ppid = int.tryParse(parts[1]);
          final cpu = double.tryParse(parts[2].replaceAll(',', '.'));
          final rss = int.tryParse(parts[3]);
          if (pid == null || ppid == null || cpu == null || rss == null) continue;
          own[pid] = ProcStats(cpu: cpu, memoryKb: rss);
          children.putIfAbsent(ppid, () => []).add(pid);
        }
      }

      final out = <int, ProcStats>{};
      for (final root in roots) {
        if (!own.containsKey(root)) continue;
        var total = const ProcStats(cpu: 0, memoryKb: 0);
        final queue = <int>[root];
        final seen = <int>{};
        while (queue.isNotEmpty) {
          final pid = queue.removeLast();
          if (!seen.add(pid)) continue;
          total = total + (own[pid] ?? const ProcStats(cpu: 0, memoryKb: 0));
          queue.addAll(children[pid] ?? const []);
        }
        out[root] = total;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}

typedef WinProcess = ({int pid, int ppid, int cpuTime, int memoryBytes});

/// Every process on Windows: pid, parent pid, CPU time (100 ns units) and working set.
// shortcut: starts PowerShell (~0.3 s) per call; move to a native call if sampling feels heavy.
Future<List<WinProcess>> windowsProcesses() async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r"Get-CimInstance Win32_Process | ForEach-Object { '{0} {1} {2} {3}' -f $_.ProcessId,$_.ParentProcessId,($_.KernelModeTime+$_.UserModeTime),$_.WorkingSetSize }",
  ]).timeout(const Duration(seconds: 10));
  return parseWindowsProcesses(r.stdout as String);
}

List<WinProcess> parseWindowsProcesses(String out) => [
      for (final line in out.split('\n'))
        if (line.trim().split(' ') case [final a, final b, final c, final d])
          if ((int.tryParse(a), int.tryParse(b), int.tryParse(c), int.tryParse(d))
              case (final int pid, final int ppid, final int cpu, final int mem))
            (pid: pid, ppid: ppid, cpuTime: cpu, memoryBytes: mem),
    ];
