import 'package:appy/services/helpers.dart';
import 'package:appy/services/port_scanner.dart';
import 'package:appy/services/resource_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('netstat + tasklist → listening dev ports', () {
    final names = PortScanner.parseTasklist('"System","4","Services","0","144 K"\r\n'
        '"node.exe","5120","Console","1","81.204 K"\r\n'
        '"postgres.exe","880","Services","0","9.120 K"\r\n');
    expect(names, {4: 'System', 5120: 'node', 880: 'postgres'});

    final ports = PortScanner.parseNetstat('''
Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING       4
  TCP    0.0.0.0:5432           0.0.0.0:0              ABHÖREN         880
  TCP    127.0.0.1:5173         0.0.0.0:0              LISTENING       5120
  TCP    127.0.0.1:5173         127.0.0.1:50122        ESTABLISHED     5120
  TCP    [::]:5432              [::]:0                 LISTENING       880
  TCP    [::1]:5173             [::]:0                 LISTENING       5120
  UDP    0.0.0.0:5353           *:*                                    1234
''', names);
    expect([for (final p in ports) '${p.port} ${p.pid} ${p.command} ${p.address}'],
        ['5173 5120 node 127.0.0.1', '5432 880 postgres *']);
  });

  test('CIM process lines', () {
    final procs = parseWindowsProcesses('0 0 0 8192\r\n5120 900 31250000 104857600\r\ngarbage\r\n');
    expect(procs, [
      (pid: 0, ppid: 0, cpuTime: 0, memoryBytes: 8192),
      (pid: 5120, ppid: 900, cpuTime: 31250000, memoryBytes: 104857600),
    ]);
  });

  test('Windows helpers are PowerShell without double quotes inside', () {
    final kill = killPortCommand(3000, windows: true);
    expect(killPortTarget(kill), 3000);
    final open = windowsHelpers.firstWhere((h) => h.label == 'Open URL').build('http://localhost:5173/?q="x"%20');
    expect(open, 'powershell -NoProfile -Command "Start-Process \'http://localhost:5173/?q=%22x%22%20\'"');
    for (final h in windowsHelpers.skip(1)) {
      final cmd = h.build('3000') ?? h.build('http://localhost:3000')!;
      final script = cmd.substring('powershell -NoProfile -Command "'.length, cmd.length - 1);
      expect(script, isNot(contains('"')), reason: h.label);
    }
  });
}
