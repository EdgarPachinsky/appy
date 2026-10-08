import 'dart:io';

/// Branch + working-tree state of a project folder.
class GitInfo {
  const GitInfo({required this.branch, this.changes = 0, this.ahead = 0, this.behind = 0});

  final String branch;

  /// Number of changed / untracked files.
  final int changes;
  final int ahead;
  final int behind;

  bool get isClean => changes == 0;

  @override
  bool operator ==(Object other) =>
      other is GitInfo &&
      other.branch == branch &&
      other.changes == changes &&
      other.ahead == ahead &&
      other.behind == behind;

  @override
  int get hashCode => Object.hash(branch, changes, ahead, behind);
}

class GitStatus {
  /// Returns null when the folder is not inside a git repository
  /// (or git is unavailable).
  static Future<GitInfo?> read(String path, Map<String, String> env) async {
    try {
      final result = await Process.run(
        'git',
        ['-C', path, 'status', '--porcelain=v1', '--branch', '--untracked-files=normal'],
        environment: {...env, 'GIT_OPTIONAL_LOCKS': '0'},
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;

      final lines = (result.stdout as String).split('\n').where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty || !lines.first.startsWith('## ')) return null;

      var header = lines.first.substring(3);
      var branch = header;
      var ahead = 0, behind = 0;

      if (header.startsWith('No commits yet on ')) {
        branch = header.substring('No commits yet on '.length);
      } else if (header.startsWith('HEAD (no branch)')) {
        final sha = await Process.run('git', ['-C', path, 'rev-parse', '--short', 'HEAD'],
            environment: env, includeParentEnvironment: false);
        branch = 'detached ${(sha.stdout as String).trim()}';
      } else {
        final bracket = header.indexOf(' [');
        if (bracket != -1) {
          final info = header.substring(bracket + 2, header.length - 1);
          ahead = int.tryParse(RegExp(r'ahead (\d+)').firstMatch(info)?.group(1) ?? '') ?? 0;
          behind = int.tryParse(RegExp(r'behind (\d+)').firstMatch(info)?.group(1) ?? '') ?? 0;
          header = header.substring(0, bracket);
        }
        final dots = header.indexOf('...');
        branch = dots == -1 ? header : header.substring(0, dots);
      }

      return GitInfo(branch: branch, changes: lines.length - 1, ahead: ahead, behind: behind);
    } catch (_) {
      return null;
    }
  }
}
