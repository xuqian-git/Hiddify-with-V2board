import Foundation
import Combine

/// 新接口调用示例
class HiddifyDemo {
    private let service = HiddifyService(configPath: FilePath.sharedDirectory.appendingPathComponent("config.json").path)
    private var cancellables = Set<AnyCancellable>()
    
    func demo() {
        // 启动服务
        do {
            try service.startService()
            service.connectStatusClient()
        } catch {
            print("启动失败: \(error)")
        }
        
        // 订阅状态更新
        service.commandClient?.statusPublisher
            .sink { status in
                print("当前连接数: \(status.connections)")
                print("内存占用: \(status.memory) bytes")
                print("实时流量 ↑\(status.trafficOut) ↓\(status.trafficIn)")
            }
            .store(in: &cancellables)
        
        // 节点操作示例
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            do {
                try self.service.selectOutbound(groupTag: "proxy", outboundTag: "hk-node")
                print("已切换香港节点")
            } catch {
                print("节点切换失败: \(error)")
            }
        }
        
        // 日志监控示例
        let logClient = NewCommandClient(connectionType: .log)
        logClient.logPublisher
            .sink { log in
                print("[LOG]", log)
            }
            .store(in: &cancellables)
        logClient.connect()
    }
}

// MARK: - 文件路径辅助
class FilePath {
    static let sharedDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hiddify")
    }()
}
