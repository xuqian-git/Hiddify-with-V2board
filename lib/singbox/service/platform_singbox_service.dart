// 导入必要的 Dart 和 Flutter 包
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/singbox_outbound.dart';
import 'package:hiddify/singbox/model/singbox_stats.dart';
import 'package:hiddify/singbox/model/singbox_status.dart';
import 'package:hiddify/singbox/model/warp_account.dart';
import 'package:hiddify/singbox/service/singbox_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:rxdart/rxdart.dart';

// PlatformSingboxService 类实现了 SingboxService 接口，并使用 InfraLogger 进行日志记录
class PlatformSingboxService with InfraLogger implements SingboxService {
  // 定义用于与 Flutter 通信的通道前缀
  static const channelPrefix = "buzz.fanyo";

  // 定义用于方法调用的通道
  static const methodChannel = MethodChannel("$channelPrefix/method");
  // 定义用于接收服务状态的事件通道
  static const statusChannel = EventChannel("$channelPrefix/service.status", JSONMethodCodec());
  // 定义用于接收警报的事件通道
  static const alertsChannel = EventChannel("$channelPrefix/service.alerts", JSONMethodCodec());
  // 定义用于接收统计信息的事件通道
  static const statsChannel = EventChannel("$channelPrefix/stats", JSONMethodCodec());
  // 定义用于接收组信息的事件通道
  static const groupsChannel = EventChannel("$channelPrefix/groups");
  // 定义用于接收活跃组信息的事件通道
  static const activeGroupsChannel = EventChannel("$channelPrefix/active-groups");
  // 定义用于接收日志的事件通道
  static const logsChannel = EventChannel("$channelPrefix/service.logs");

  // 定义用于存储 Singbox 状态的流
  late final ValueStream<SingboxStatus> _status;

  // 初始化方法，异步执行
  @override
  Future<void> init() async {
    loggy.debug("initializing");  // 记录初始化日志
    // 从状态通道接收广播流并映射为 SingboxStatus 对象
    final status = statusChannel.receiveBroadcastStream().map(SingboxStatus.fromEvent);
    // 从警报通道接收广播流并映射为 SingboxStatus 对象
    final alerts = alertsChannel.receiveBroadcastStream().map(SingboxStatus.fromEvent);

    // 合并状态和警报流，并自动连接
    _status = ValueConnectableStream(Rx.merge([status, alerts])).autoConnect();
    await _status.first;  // 等待第一个状态更新
  }

  // 设置方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> setup(Directories directories, bool debug) {
    return TaskEither(
      () async {
        // 如果不是 iOS 平台，则直接返回成功
        if (!Platform.isIOS) {
          return right(unit);
        }

        // 调用 setup 方法
        await methodChannel.invokeMethod("setup");
        return right(unit);
      },
    );
  }

  // 验证配置文件方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> validateConfigByPath(
    String path,
    String tempPath,
    bool debug,
  ) {
    return TaskEither(
      () async {
        // 调用 parse_config 方法
        final message = await methodChannel.invokeMethod<String>(
          "parse_config",
          {"path": path, "tempPath": tempPath, "debug": debug},
        );
        // 如果返回消息为空，则返回成功
        if (message == null || message.isEmpty) return right(unit);
        // 否则返回错误消息
        return left(message);
      },
    );
  }

  // 修改选项方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    return TaskEither(
      () async {
        loggy.debug("changing options");  // 记录修改选项日志
        try {
          // 将选项转换为 JSON 字符串
          loggy.debug("options: ${options.toJson()}");
          // 调用 change_hiddify_options 方法
          await methodChannel.invokeMethod(
            "change_hiddify_options",
            jsonEncode(options.toJson()),
          );
          return right(unit);
        } catch (e) {
          // 打印错误信息
          print("Error calling change_hiddify_options: $e");
          // 如果是 PlatformException 类型，则不处理
          if (e is PlatformException) {

          }
          // 重新抛出异常
          rethrow;
        }
      },
    );
  }

  // 生成完整配置文件方法，返回 TaskEither 类型
  @override
  TaskEither<String, String> generateFullConfigByPath(String path) {
    return TaskEither(
      () async {
        loggy.debug("generating full config by path");  // 记录生成配置文件日志
        // 调用 generate_config 方法
        final configJson = await methodChannel.invokeMethod<String>(
          "generate_config",
          {"path": path},
        );
        // 如果返回配置文件为空，则返回错误消息
        if (configJson == null || configJson.isEmpty) {
          return left("null response");
        }
        // 否则返回配置文件
        return right(configJson);
      },
    );
  }

  // 启动服务方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> start(
    String path,
    String name,
    bool disableMemoryLimit,
  ) {
    return TaskEither(
      () async {
        loggy.debug("starting");  // 记录启动服务日志
        // 调用 start 方法
        await methodChannel.invokeMethod(
          "start",
          {"path": path, "name": name},
        );
        return right(unit);
      },
    );
  }

  // 停止服务方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> stop() {
    return TaskEither(
      () async {
        loggy.debug("stopping");  // 记录停止服务日志
        // 调用 stop 方法
        await methodChannel.invokeMethod("stop");
        return right(unit);
      },
    );
  }

  // 重启服务方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> restart(
    String path,
    String name,
    bool disableMemoryLimit,
  ) {
    return TaskEither(
      () async {
        loggy.debug("restarting");  // 记录重启服务日志
        // 调用 restart 方法
        await methodChannel.invokeMethod(
          "restart",
          {"path": path, "name": name},
        );
        return right(unit);
      },
    );
  }

  // 重置隧道方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> resetTunnel() {
    return TaskEither(
      () async {
        // 只有在 iOS 平台上才可用
        if (!Platform.isIOS) {
          throw UnimplementedError(
            "reset tunnel function unavailable on platform",
          );
        }

        loggy.debug("resetting tunnel");  // 记录重置隧道日志
        // 调用 reset 方法
        await methodChannel.invokeMethod("reset");
        return right(unit);
      },
    );
  }

  // 监听组信息方法，返回流
  @override
  Stream<List<SingboxOutboundGroup>> watchGroups() {
    loggy.debug("watching groups");  // 记录监听组信息日志
    // 从组信息通道接收广播流并映射为 SingboxOutboundGroup 对象
    return groupsChannel.receiveBroadcastStream().map(
      (event) {
        if (event case String _) {
          return (jsonDecode(event) as List).map((e) {
            return SingboxOutboundGroup.fromJson(e as Map<String, dynamic>);
          }).toList();
        }
        loggy.error("[group client] unexpected type, msg: $event");
        throw "invalid type";
      },
    );
  }

  // 监听活跃组信息方法，返回流
  @override
  Stream<List<SingboxOutboundGroup>> watchActiveGroups() {
    loggy.debug("watching active groups");  // 记录监听活跃组信息日志
    // 从活跃组信息通道接收广播流并映射为 SingboxOutboundGroup 对象
    return activeGroupsChannel.receiveBroadcastStream().map(
      (event) {
        if (event case String _) {
          return (jsonDecode(event) as List).map((e) {
            return SingboxOutboundGroup.fromJson(e as Map<String, dynamic>);
          }).toList();
        }
        loggy.error("[active group client] unexpected type, msg: $event");
        throw "invalid type";
      },
    );
  }

  // 监听服务状态方法，返回流
  @override
  Stream<SingboxStatus> watchStatus() => _status;

  // 监听统计信息方法，返回流
  @override
  Stream<SingboxStats> watchStats() {
    loggy.debug("watching stats");  // 记录监听统计信息日志
    // 从统计信息通道接收广播流并映射为 SingboxStats 对象
    return statsChannel.receiveBroadcastStream().map(
      (event) {
        if (event case Map<String, dynamic> _) {
          return SingboxStats.fromJson(event);
        }
        loggy.error(
          "[stats client] unexpected type(${event.runtimeType}), msg: $event",
        );
        throw "invalid type";
      },
    );
  }

  // 选择出站方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    return TaskEither(
      () async {
        loggy.debug("selecting outbound");  // 记录选择出站日志
        // 调用 select_outbound 方法
        await methodChannel.invokeMethod(
          "select_outbound",
          {"groupTag": groupTag, "outboundTag": outboundTag},
        );
        return right(unit);
      },
    );
  }

  // URL 测试方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> urlTest(String groupTag) {
    return TaskEither(
      () async {
        // 调用 url_test 方法
        await methodChannel.invokeMethod(
          "url_test",
          {"groupTag": groupTag},
        );
        return right(unit);
      },
    );
  }

  // 监听日志方法，返回流
  @override
  Stream<List<String>> watchLogs(String path) async* {
    yield* logsChannel.receiveBroadcastStream().map((event) => (event as List).map((e) => e as String).toList());
  }

  // 清除日志方法，返回 TaskEither 类型
  @override
  TaskEither<String, Unit> clearLogs() {
    return TaskEither(
      () async {
        // 调用 clear_logs 方法
        await methodChannel.invokeMethod("clear_logs");
        return right(unit);
      },
    );
  }

  // 生成 Warp 配置方法，返回 TaskEither 类型
  @override
  TaskEither<String, WarpResponse> generateWarpConfig({
    required String licenseKey,
    required String previousAccountId,
    required String previousAccessToken,
  }) {
    return TaskEither(
      () async {
        loggy.debug("generating warp config");  // 记录生成 Warp 配置日志
        // 调用 generate_warp_config 方法
        final warpConfig = await methodChannel.invokeMethod(
          "generate_warp_config",
          {
            "license-key": licenseKey,
            "previous-account-id": previousAccountId,
            "previous-access-token": previousAccessToken,
          },
        );
        // 将返回的配置转换为 WarpResponse 对象
        return right(warpFromJson(jsonDecode(warpConfig as String)));
      },
    );
  }
}
