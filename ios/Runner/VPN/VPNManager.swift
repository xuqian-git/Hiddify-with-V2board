//
//  VPNManager.swift
//  Runner
//
//  Created by GFWFighter on 7/25/1402 AP.
//

// VPN管理类，负责处理VPN连接状态、统计信息等
import Foundation
import Combine
import NetworkExtension

// VPN相关警告类型枚举
enum VPNManagerAlertType: String {
    case RequestVPNPermission  // 请求VPN权限
    case RequestNotificationPermission  // 请求通知权限
    case EmptyConfiguration  // 空配置
    case StartCommandServer  // 启动命令服务器
    case CreateService  // 创建服务
    case StartService  // 启动服务
}

struct VPNManagerAlert {
    let alert: VPNManagerAlertType?
    let message: String?
}

class VPNManager: ObservableObject {
    // Combine取消订阅集合
    private var cancelBag: Set<AnyCancellable> = []

    // 状态观察者
    private var observer: NSObjectProtocol?
    // VPN管理器实例
    private var manager = NEVPNManager.shared()
    // 是否已加载配置
    private var loaded: Bool = false
    // 定时器，用于更新统计信息
    private var timer: Timer?

    // 单例实例
    static let shared: VPNManager = VPNManager()

    // 当前VPN状态
    @Published private(set) var state: NEVPNStatus = .invalid
    // 警告信息
    @Published private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil)

    // 上传流量统计
    @Published private(set) var upload: Int64 = 0
    // 下载流量统计
    @Published private(set) var download: Int64 = 0
    // 连接持续时间
    @Published private(set) var elapsedTime: TimeInterval = 0

    // 连接时间存储
    private var _connectTime: Date?
    // 连接时间计算属性，持久化到UserDefaults
    private var connectTime: Date? {
        set {
            UserDefaults(suiteName: FilePath.groupName)?.set(newValue?.timeIntervalSince1970, forKey: "SingBoxConnectTime")
            _connectTime = newValue
        }
        get {
            if let _connectTime {
                return _connectTime
            }
            guard let interval = UserDefaults(suiteName: FilePath.groupName)?.value(forKey: "SingBoxConnectTime") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }
    // WebSocket读取状态
    private var readingWS: Bool = false

    // 是否连接到任意VPN的状态
    @Published var isConnectedToAnyVPN: Bool = false

    init() {
        // 监听VPN状态变化
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: nil) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            self?.state = connection.status
        }

        // 启动定时器，每秒更新统计信息
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateStats()
            elapsedTime = -1 * (connectTime?.timeIntervalSinceNow ?? 0)
        }
    }

    deinit {
        // 清理观察者和定时器
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
    }

    // 初始化设置
    func setup() async throws {
        // guard !loaded else { return }
        loaded = true
        do {
            try await loadVPNPreference()
        } catch {
            print(error.localizedDescription)
        }
    }

    // 加载VPN配置
    private func loadVPNPreference() async throws {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let manager = managers.first {
                self.manager = manager
                return
            }
            // 创建新的VPN管理器
            let newManager = NETunnelProviderManager()
            let `protocol` = NETunnelProviderProtocol()
            `protocol`.providerBundleIdentifier = Bundle.main.baseBundleIdentifier + ".HiddifyPacketTunnel"
            `protocol`.serverAddress = "localhost"
            newManager.protocolConfiguration = `protocol`
            newManager.localizedDescription = "Hiddify"
            try await newManager.saveToPreferences()
            try await newManager.loadFromPreferences()
            self.manager = newManager
        } catch {
            print(error.localizedDescription)
        }
    }

    // 启用VPN管理器
    private func enableVPNManager() async throws {
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
            print(error.localizedDescription)
        }
    }

    // 更新流量统计（主线程）
    @MainActor private func set(upload: Int64, download: Int64) {
        self.upload = upload
        self.download = download
    }

    // 检查是否连接到任意VPN
    var isAnyVPNConnected: Bool {
        guard let cfDict = CFNetworkCopySystemProxySettings() else { return false }
        let nsDict = cfDict.takeRetainedValue() as NSDictionary
        guard let keys = nsDict["__SCOPED__"] as? NSDictionary else {
            return false
        }
        // 检查常见VPN接口
        for key: String in keys.allKeys as! [String] {
            if key == "tap" || key == "tun" || key == "ppp" || key == "ipsec" || key == "ipsec0" {
                return true
            } else if key.starts(with: "utun") {
                return true
            }
        }
        return false
    }

    // 重置VPN管理器
    func reset() {
        loaded = false
        if state != .disconnected && state != .invalid {
            disconnect()
        }
        // 监听状态变化，完成后重新加载配置
        $state.filter { $0 == .disconnected || $0 == .invalid }.first().sink { [weak self] _ in
            Task { [weak self] () in
                self?.manager = .shared()
                do {
                    let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                    for manager in managers ?? [] {
                        try await manager.removeFromPreferences()
                    }
                    try await self?.loadVPNPreference()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }.store(in: &cancelBag)
    }

    // 更新统计信息
    private func updateStats() {
        let isAnyVPNConnected = self.isAnyVPNConnected
        if isConnectedToAnyVPN != isAnyVPNConnected {
            isConnectedToAnyVPN = isAnyVPNConnected
        }
        guard state == .connected else { return }
        guard let connection = manager.connection as? NETunnelProviderSession else { return }
        do {
            // 发送统计信息请求
            try connection.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard
                    let response,
                    let response = String(data: response, encoding: .utf8)
                else { return }
                // 解析上传下载流量
                let responseComponents = response.components(separatedBy: ",")
                guard
                    responseComponents.count == 2,
                    let upload = Int64(responseComponents[0]),
                    let download = Int64(responseComponents[1])
                else { return }
                Task { [upload, download, weak self] () in
                    await self?.set(upload: upload, download: download)
                }
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    // 连接VPN
    func connect(with config: String, disableMemoryLimit: Bool = false) async throws {
        await set(upload: 0, download: 0)
        guard state == .disconnected else { return }
        do {
            try await enableVPNManager()
            // 启动VPN隧道
            try manager.connection.startVPNTunnel(options: [
                "Config": config as NSString,
                "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
            ])
        } catch {
            print(error.localizedDescription)
        }
        connectTime = .now
    }

    // 断开VPN连接
    func disconnect() {
        guard state == .connected else { return }
        manager.connection.stopVPNTunnel()
    }
}
