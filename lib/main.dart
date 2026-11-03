import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'data/repository.dart';
import 'services/audio_handler.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 沉浸式：系统状态栏 / 手势条全透明，内容延伸到屏幕边缘
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  final repo = LibraryRepository();
  final state = AppState(repo);
  await state.init();

  // Android 13+ 通知栏媒体控件需要运行时通知权限；
  // 没授权时系统看不到我们的「正在播放」卡片。静默申请一次，拒绝也不打扰。
  // ignore: unawaited_futures
  Permission.notification.request();

  // 接管系统播放控件：通知栏 / 锁屏 / 耳机按键 / 系统媒体卡
  CloudTuneHandler? handler;
  try {
    handler = await AudioService.init(
      builder: () => CloudTuneHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.cloudtune.player.channel.audio',
        androidNotificationChannelName: 'Nebu 播放',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
        androidShowNotificationBadge: false,
      ),
    );
  } catch (_) {
    // 初始化失败也不影响正常播放，只是没有通知栏控制
  }

  runApp(CloudTuneApp(app: state, handler: handler));

  // 启动后静默检查一次更新：失败完全无感，发现新版只在「我的」页亮起入口
  state.scheduleStartupUpdateCheck();
}
