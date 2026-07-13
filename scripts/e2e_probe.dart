// E2E 探针：经 Chrome DevTools 协议驱动无头 Edge，对运行中的 Web 版
// 做真实点击/输入/截图（CanvasKit 无 DOM 语义，验证只能靠像素与行为）。
//
// 用法（先启动带 --remote-debugging-port=9222 的 Edge）：
//   dart run scripts/e2e_probe.dart open http://127.0.0.1:8788   # 打开页面
//   dart run scripts/e2e_probe.dart tap 195 422                  # 点击逻辑坐标
//   dart run scripts/e2e_probe.dart text 永夜                     # 输入文本
//   dart run scripts/e2e_probe.dart shot C:\tmp\a.png            # 截图
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _port = 9222;
final _stateFile = File(
  '${Platform.environment['TEMP'] ?? '/tmp'}/e2e_probe_target.txt',
);

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: open <url> | tap <x> <y> | text <str> | shot <file>');
    exit(2);
  }
  final cmd = args[0];

  if (cmd == 'open') {
    final url = Uri.encodeComponent(args[1]);
    final res = await _httpPut('/json/new?$url');
    final id = (jsonDecode(res) as Map)['id'] as String;
    _stateFile.writeAsStringSync(id);
    stdout.writeln('target=$id');
    return;
  }

  final targetId = _stateFile.readAsStringSync().trim();
  final list = jsonDecode(await _httpGet('/json/list')) as List;
  final target = list.cast<Map>().firstWhere(
    (t) => t['id'] == targetId,
    orElse: () => throw StateError('target 不存在，先 open'),
  );
  final ws = await WebSocket.connect(target['webSocketDebuggerUrl'] as String);
  var seq = 0;
  final pending = <int, Completer<Map>>{};
  // 广播流：命令回复与事件（console/异常）两路都要消费
  final events = ws.asBroadcastStream();
  events.listen((raw) {
    final msg = jsonDecode(raw as String) as Map;
    final id = msg['id'];
    if (id is int) pending.remove(id)?.complete(msg);
  });
  Future<Map> send(String method, [Map? params]) {
    final id = ++seq;
    final c = Completer<Map>();
    pending[id] = c;
    ws.add(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    return c.future.timeout(const Duration(seconds: 20));
  }

  switch (cmd) {
    case 'tapwatch':
      // 点击并收集其后 N 秒的 console 输出与未捕获异常（诊断白屏）
      final x = double.parse(args[1]), y = double.parse(args[2]);
      final seconds = args.length > 3 ? int.parse(args[3]) : 6;
      await send('Runtime.enable');
      await send('Log.enable');
      final done = Completer<void>();
      Timer(Duration(seconds: seconds), () => done.complete());
      events.listen((raw) {
        final msg = jsonDecode(raw as String) as Map;
        final method = msg['method'];
        if (method == 'Runtime.exceptionThrown') {
          stdout.writeln('[异常] ${jsonEncode(msg['params'])}');
        } else if (method == 'Runtime.consoleAPICalled') {
          final p = msg['params'] as Map;
          final vals = (p['args'] as List)
              .map((a) => (a as Map)['value'] ?? a['description'] ?? '')
              .join(' ');
          stdout.writeln('[console.${p['type']}] $vals');
        } else if (method == 'Log.entryAdded') {
          final e = (msg['params'] as Map)['entry'] as Map;
          stdout.writeln('[log.${e['level']}] ${e['text']}');
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      for (final type in ['mousePressed', 'mouseReleased']) {
        await send('Input.dispatchMouseEvent', {
          'type': type,
          'x': x,
          'y': y,
          'button': 'left',
          'clickCount': 1,
        });
      }
      stdout.writeln('tapped $x,$y — 监听 $seconds 秒…');
      await done.future;
    case 'tap':
      final x = double.parse(args[1]), y = double.parse(args[2]);
      for (final type in ['mousePressed', 'mouseReleased']) {
        await send('Input.dispatchMouseEvent', {
          'type': type,
          'x': x,
          'y': y,
          'button': 'left',
          'clickCount': 1,
        });
      }
      stdout.writeln('tapped $x,$y');
    case 'hold':
      // 长按：按下→保持 ms 毫秒→抬起（复现长按星球弹删除确认）
      final hx = double.parse(args[1]), hy = double.parse(args[2]);
      final ms = args.length > 3 ? int.parse(args[3]) : 700;
      await send('Input.dispatchMouseEvent', {
        'type': 'mousePressed',
        'x': hx,
        'y': hy,
        'button': 'left',
        'clickCount': 1,
      });
      await Future<void>.delayed(Duration(milliseconds: ms));
      await send('Input.dispatchMouseEvent', {
        'type': 'mouseReleased',
        'x': hx,
        'y': hy,
        'button': 'left',
        'clickCount': 1,
      });
      stdout.writeln('held $hx,$hy ${ms}ms');
    case 'swipe':
      // 拖拽手势：按下→多步移动→抬起（复现 PageView 左右滑切星球）
      final x0 = double.parse(args[1]), y0 = double.parse(args[2]);
      final x1 = double.parse(args[3]), y1 = double.parse(args[4]);
      await send('Input.dispatchMouseEvent', {
        'type': 'mousePressed',
        'x': x0,
        'y': y0,
        'button': 'left',
        'clickCount': 1,
      });
      const steps = 12;
      for (var i = 1; i <= steps; i++) {
        await send('Input.dispatchMouseEvent', {
          'type': 'mouseMoved',
          'x': x0 + (x1 - x0) * i / steps,
          'y': y0 + (y1 - y0) * i / steps,
          'button': 'left',
        });
        // 步间留时差：Flutter 拖动识别器要靠时间差算速度，瞬时突进会被判成无效
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      await send('Input.dispatchMouseEvent', {
        'type': 'mouseReleased',
        'x': x1,
        'y': y1,
        'button': 'left',
        'clickCount': 1,
      });
      stdout.writeln('swiped $x0,$y0 -> $x1,$y1');
    case 'text':
      await send('Input.insertText', {'text': args[1]});
      stdout.writeln('typed');
    case 'throttle':
      // 模拟手机：CPU 降速 N 倍（复现真机加载时序/卡顿）
      await send('Emulation.setCPUThrottlingRate', {
        'rate': double.parse(args[1]),
      });
      stdout.writeln('cpu throttle x${args[1]}');
    case 'eval':
      final r = await send('Runtime.evaluate', {
        'expression': args[1],
        'returnByValue': true,
      });
      stdout.writeln(jsonEncode((r['result'] as Map)['result']));
    case 'shot':
      final r = await send('Page.captureScreenshot', {'format': 'png'});
      final b64 = ((r['result'] as Map)['data']) as String;
      File(args[1]).writeAsBytesSync(base64Decode(b64));
      stdout.writeln('saved ${args[1]}');
    default:
      stderr.writeln('未知命令 $cmd');
      exit(2);
  }
  await ws.close();
}

Future<String> _httpGet(String path) async {
  final c = HttpClient();
  final req = await c.get('127.0.0.1', _port, path);
  final res = await req.close();
  return res.transform(utf8.decoder).join();
}

Future<String> _httpPut(String path) async {
  final c = HttpClient();
  final req = await c.put('127.0.0.1', _port, path);
  final res = await req.close();
  return res.transform(utf8.decoder).join();
}
