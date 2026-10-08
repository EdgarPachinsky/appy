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
  static Future<Map<int, ProcStats>> sample(Iterable<int> rootPids) async {
    final roots = rootPids.toSet();
    if (roots.isEmpty) return const {};
    try {
      final result = await Process.run('/bin/ps', ['-A', '-o', 'pid=,ppid=,%cpu=,rss=']);
      final children = <int, List<int>>{};
      final own = <int, ProcStats>{};
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
