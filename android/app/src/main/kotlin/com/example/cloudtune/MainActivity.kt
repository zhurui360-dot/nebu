package com.example.cloudtune

import io.flutter.embedding.android.FlutterActivity
import com.ryanheise.audioservice.AudioServiceActivity

/// 必须继承 AudioServiceActivity：
/// audio_service 的媒体会话要挂在这上面，通知栏/锁屏/系统媒体卡才能接管。
class MainActivity : AudioServiceActivity()
