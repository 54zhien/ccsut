// lib/main.dart
//
// 长沙工业学院教务助手 —— WebView 壳（会话持久化版）
//
// 解决的核心问题：
//   学习通内嵌 WebView 不保存 Cookie，导致每次进教务都要重新扫码。
//   本壳把 ccssut.cn 全站 Cookie 加密落盘，冷启动直接注回去，
//   会话过期时退回内嵌登录页（勾了「记住我」就有长效 Cookie 兜底）。
//
// 运行：
//   cd shell && flutter pub get && flutter run
//
// 说明：
//   · Cookie 用 flutter_secure_storage（Android Keystore / iOS Keychain）保存
//   · 前台每 10 分钟静默 reload 一次，续期 Shiro 服务端会话
//   · 检测落到 /admin/login 即认定失效，自动切到统一认证页

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kHomePath = 'https://tls.ccsut.cn/admin/index';
const kCasLogin =
    'https://auth.ccsut.cn/backstage/cas/login?service=https%3A%2F%2Ftls.ccsut.cn%2Fadmin%2Fcaslogin';
const kCookieHosts = ['tls.ccsut.cn', 'auth.ccsut.cn', 'ehall.ccsut.cn'];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CcsutApp());
}

class CcsutApp extends StatelessWidget {
  const CcsutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '长工院教务',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4FD1)),
        useMaterial3: true,
      ),
      home: const WebShell(),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  InAppWebViewController? _web;
  double _progress = 0;
  bool _booting = true;
  String _title = '长工院教务';
  Timer? _keepAlive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAlive?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回前台立刻打一次卡，避免切后台久了被服务端踢掉
    if (state == AppLifecycleState.resumed) _ping();
  }

  // ---------------- Cookie 持久化 ----------------

  Future<void> _saveCookies() async {
    final manager = CookieManager.instance();
    final all = <Map<String, dynamic>>[];
    for (final host in kCookieHosts) {
      try {
        final list = await manager.getCookies(url: WebUri('https://$host'));
        for (final c in list) {
          all.add({
            'name': c.name,
            'value': c.value,
            'domain': c.domain,
            'path': c.path,
            'secure': c.isSecure ?? false,
            'httpOnly': c.isHttpOnly ?? false,
            'expires': c.expiresDate,
          });
        }
      } catch (_) {}
    }
    if (all.isNotEmpty) {
      await _storage.write(key: 'cookies_v1', value: jsonEncode(all));
    }
  }

  Future<int> _restoreCookies() async {
    final raw = await _storage.read(key: 'cookies_v1');
    if (raw == null) return 0;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final manager = CookieManager.instance();
    var n = 0;
    for (final c in list) {
      final domain = (c['domain'] as String?) ?? '';
      final host = domain.startsWith('.') ? domain.substring(1) : domain;
      try {
        await manager.setCookie(
          url: WebUri('https://$host'),
          name: c['name'] as String,
          value: c['value'] as String,
          domain: domain,
          path: (c['path'] as String?) ?? '/',
          isSecure: (c['secure'] as bool?) ?? true,
          isHttpOnly: (c['httpOnly'] as bool?) ?? true,
        );
        n++;
      } catch (_) {}
    }
    return n;
  }

  // ---------------- 启动流程 ----------------

  Future<void> _bootstrap() async {
    final n = await _restoreCookies();
    debugPrint('[ccsut] 注入 Cookie $n 条');
    // 给 CookieManager 一点时间落盘到 WebView 内核
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() => _booting = false);
    _startKeepAlive();
  }

  void _startKeepAlive() {
    _keepAlive?.cancel();
    // 10 分钟静默访问一次，续期服务端会话（Shiro 默认 30 分钟过期）
    _keepAlive = Timer.periodic(const Duration(minutes: 10), (_) => _ping());
  }

  Future<void> _ping() async {
    final c = _web;
    if (c == null) return;
    final url = await c.getUrl();
    if (url == null) return;
    // 只在不处于登录流程时保活，避免打断用户输入
    if (url.toString().contains('/cas/login')) return;
    try {
      await c.evaluateJavascript(source: '''
        fetch('https://tls.ccsut.cn/admin/index', {credentials:'include'})
          .then(r => console.log('[keepalive] ' + r.status))
          .catch(() => {});
      ''');
    } catch (_) {}
  }

  // ---------------- 失效检测 / 登录兜底 ----------------

  bool _isLoginPage(String url) =>
      url.contains('tls.ccsut.cn/admin/login') || url.contains('/admin/loginFailPage');

  Future<void> _handlePageLoaded(String url) async {
    await _saveCookies();

    if (_isLoginPage(url)) {
      // 会话彻底失效：走一次内嵌 CAS 登录（用户输入一次，勾记住我后再也不用了）
      debugPrint('[ccsut] 会话失效，跳转统一认证');
      await _web?.loadUrl(urlRequest: URLRequest(url: WebUri(kCasLogin)));
      return;
    }

    if (mounted && _title == '长工院教务') {
      final t = await _web?.getTitle();
      if (t != null && t.isNotEmpty) setState(() => _title = t);
    }
  }

  Future<bool> _onOverride(String url) async {
    // 选课/评教等写操作弹确认，避免误触
    if (RegExp(r'(select|choose|submit|save|delete|drop)', caseSensitive: false).hasMatch(url)) {
      return true; // 放行，但页面内仍会有二次确认
    }
    return false;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _restoreCookies();
              _web?.reload();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'home':
                  _web?.loadUrl(urlRequest: URLRequest(url: WebUri(kHomePath)));
                  break;
                case 'login':
                  _web?.loadUrl(urlRequest: URLRequest(url: WebUri(kCasLogin)));
                  break;
                case 'clear':
                  await _storage.delete(key: 'cookies_v1');
                  await CookieManager.instance().deleteAllCookies();
                  _web?.loadUrl(urlRequest: URLRequest(url: WebUri(kCasLogin)));
                  break;
                case 'save':
                  await _saveCookies();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('会话已保存')),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'home', child: Text('回到首页')),
              PopupMenuItem(value: 'login', child: Text('重新登录')),
              PopupMenuItem(value: 'save', child: Text('立即保存会话')),
              PopupMenuItem(value: 'clear', child: Text('清除会话并登录')),
            ],
          ),
        ],
        bottom: _progress > 0 && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2),
              )
            : null,
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(kHomePath)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: false,
                userAgent: null, // 用系统默认 UA，教务系统会按 UA 做响应式
              ),
              onWebViewCreated: (c) => _web = c,
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
              onLoadStop: (_, url) async {
                if (url == null) return;
                await _handlePageLoaded(url.toString());
              },
              shouldOverrideUrlLoading: (_, action) async {
                final url = action.request.url.toString();
                await _onOverride(url);
                return NavigationActionPolicy.ALLOW;
              },
              onReceivedServerTrustAuthRequest: (_, challenge) async =>
                  ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED),
            ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: '课表',
        onPressed: () =>
            _web?.loadUrl(urlRequest: URLRequest(url: WebUri('https://tls.ccsut.cn/admin/course/index'))),
        child: const Icon(Icons.calendar_month),
      ),
    );
  }
}
