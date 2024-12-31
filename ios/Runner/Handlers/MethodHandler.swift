//
//  MethodHandler.swift
//  Runner
//
//  Created by GFWFighter on 10/23/23.
//

import Flutter
import Combine
import Libcore

public class MethodHandler: NSObject, FlutterPlugin {

    private var cancelBag: Set<AnyCancellable> = []

    public static let name = "\(Bundle.main.serviceIdentifier)/method"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
        let instance = MethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }

    private var channel: FlutterMethodChannel?

    // 处理来自 Flutter 的方法调用
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // 定义一个在主线程返回结果的函数
        @Sendable func mainResult(_ res: Any?) async -> Void {
            await MainActor.run {
                result(res)
            }
        }

        switch call.method {
        case "parse_config":
            // 解析配置文件
            // 需要三个参数:
            // - path: 配置文件路径
            // - tempPath: 临时文件路径
            // - debug: 是否开启调试模式
            guard
                let args = call.arguments as? [String:Any?],
                let path = args["path"] as? String,
                let tempPath = args["tempPath"] as? String,
                let debug = (args["debug"] as? NSNumber)?.boolValue
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            
            print("参数列表:")
            print("path: \(path)")
            print("tempPath: \(tempPath)") 
            print("debug: \(debug)")
            var error: NSError?
            MobileParse(path, tempPath, debug, &error)
            if let error {
                result(FlutterError(code: String(error.code), message: error.description, details: nil))
                return
            }
            result("")
            
        case "change_hiddify_options":
            // 更改 Hiddify 选项配置
            guard let options = call.arguments as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            VPNConfig.shared.configOptions = options
            result(true)
            
        case "setup":
            // 设置 VPN
            Task {
                do {
                    try await VPNManager.shared.setup()
                } catch {
                    await mainResult(FlutterError(code: "SETUP", message: error.localizedDescription, details: nil))
                    return
                }
                await mainResult(true)
            }
            
        case "start":
            // 启动 VPN 连接
            // 需要配置文件路径参数
            // Task 是 Swift 5.5 引入的异步并发特性
            // 创建一个异步上下文来执行网络请求等耗时操作
            // 使用 async/await 语法可以避免回调地狱
            Task {
                // 从 Flutter 传入的参数中获取配置文件路径
                guard
                    let args = call.arguments as? [String:Any?],
                    let path = args["path"] as? String
                else {
                    print("参数无效")
                    await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                
                // 打印参数
                print("参数列表:")
                print("path: \(path)")
                
                // 保存当前活动的配置文件路径
                VPNConfig.shared.activeConfigPath = path
                
                // 根据配置文件路径构建 VPN 配置
                var error: NSError?
                let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
                if let error {
                    print("构建配置失败: \(error.description)")
                    await mainResult(FlutterError(code: String(error.code), message: error.description, details: nil))
                    return
                }
                
                do {
                    // 设置并启动 VPN 连接
                    try await VPNManager.shared.setup()
                    try await VPNManager.shared.connect(with: config, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit)
                } catch {
                    print("设置连接失败: \(error.localizedDescription)")
                    await mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                    return
                }
                
                // 成功启动 VPN 连接
                await mainResult(true)
            }
            
        case "restart":
            // 重启 VPN 连接
            // 需要配置文件路径参数
            Task { [unowned self] in
                guard
                    let args = call.arguments as? [String:Any?],
                    let path = args["path"] as? String
                else {
                    await mainResult(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                VPNConfig.shared.activeConfigPath = path
                VPNManager.shared.disconnect()
                await waitForStop().value
                var error: NSError?
                let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
                if let error {
                    await mainResult(FlutterError(code: "BUILD_CONFIG", message: error.localizedDescription, details: nil))
                    return
                }
                do {
                    try await VPNManager.shared.setup()
                    try await VPNManager.shared.connect(with: config, disableMemoryLimit: VPNConfig.shared.disableMemoryLimit)
                } catch {
                    await mainResult(FlutterError(code: "SETUP_CONNECTION", message: error.localizedDescription, details: nil))
                    return
                }
                await mainResult(true)
            }
            
        case "stop":
            // 停止 VPN 连接
            VPNManager.shared.disconnect()
            result(true)
            
        case "reset":
            // 重置 VPN 管理器
            VPNManager.shared.reset()
            result(true)
            
        case "url_test":
            // 执行 URL 测试
            // 可选参数: groupTag - 分组标签
            guard
                let args = call.arguments as? [String:Any?]
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let group = args["groupTag"] as? String
            FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
            do {
                try LibboxNewStandaloneCommandClient()?.urlTest(group)
            } catch {
                result(FlutterError(code: "URL_TEST", message: error.localizedDescription, details: nil))
                return
            }
            result(true)
            
        case "select_outbound":
            // 选择出站连接
            // 需要两个参数:
            // - groupTag: 分组标签
            // - outboundTag: 出站标签
            guard
                let args = call.arguments as? [String:Any?],
                let group = args["groupTag"] as? String,
                let outbound = args["outboundTag"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
            do {
                try LibboxNewStandaloneCommandClient()?.selectOutbound(group, outboundTag: outbound)
            } catch {
                result(FlutterError(code: "SELECT_OUTBOUND", message: error.localizedDescription, details: nil))
                return
            }
            result(true)
            
        case "generate_config":
            // 生成配置
            // 需要配置文件路径参数
            guard
                let args = call.arguments as? [String:Any?],
                let path = args["path"] as? String
            else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            var error: NSError?
            let config = MobileBuildConfig(path, VPNConfig.shared.configOptions, &error)
            if let error {
                result(FlutterError(code: "BUILD_CONFIG", message: error.localizedDescription, details: nil))
                return
            }
            result(config)
            
        case "generate_warp_config":
            // 生成 WARP 配置
            // 需要三个参数:
            // - license-key: 许可证密钥
            // - previous-account-id: 之前的账户 ID
            // - previous-access-token: 之前的访问令牌
            guard let args = call.arguments as? [String: Any],
                  let licenseKey = args["license-key"] as? String,
                  let accountId = args["previous-account-id"] as? String,
                  let accessToken = args["previous-access-token"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }
            let warpConfig = MobileGenerateWarpConfig(licenseKey, accountId, accessToken, nil)
            result(warpConfig)
            
        default:
            // 未实现的方法
            result(FlutterMethodNotImplemented)
        }
    }

    private func waitForStop() -> Future<Void, Never> {
        return Future { promise in
            var cancellable: AnyCancellable? = nil
            cancellable = VPNManager.shared.$state
                .filter { $0 == .disconnected }
                .first()
                .delay(for: 0.5, scheduler: RunLoop.current)
                .sink(receiveValue: { _ in
                    promise(.success(()))
                    cancellable?.cancel()
                })
        }
    }
}
