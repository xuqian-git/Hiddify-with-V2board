import Foundation
import Libcore

public class HiddifyService {
    private var configPath: String
    private var serviceManager: ServiceManager?
    private var commandClient: NewCommandClient?
    
    public init(configPath: String) {
        self.configPath = configPath
        FileManager.default.createFile(atPath: configPath, contents: nil)
    }
    
    // MARK: - 核心服务控制
    public func startService() throws {
        serviceManager = try ServiceManager(configPath: configPath)
        try serviceManager?.start()
    }
    
    public func stopService() {
        serviceManager?.stop()
        commandClient?.disconnect()
    }
    
    // MARK: - 节点操作
    public func selectOutbound(groupTag: String, outboundTag: String) throws {
        try serviceManager?.selectOutbound(groupTag: groupTag, outboundTag: outboundTag)
    }
    
    // MARK: - 状态监控
    public func connectStatusClient() {
        commandClient = NewCommandClient(connectionType: .status)
        commandClient?.connect()
    }
}

// MARK: - 服务管理封装
private class ServiceManager {
    private let configPath: String
    private var service: LibboxService?
    
    init(configPath: String) throws {
        self.configPath = configPath
        let config = LibboxConfig()!
        config.configPath = configPath
        config.workingDirectory = FilePath.sharedDirectory.path
        service = LibboxService(config)
    }
    
    func start() throws {
        try service?.start()
    }
    
    func stop() {
        service?.close()
    }
    
    func selectOutbound(groupTag: String, outboundTag: String) throws {
        let command = LibboxCommandSelect()!
        command.groupTag = groupTag
        command.outboundTag = outboundTag
        try service?.commandClient(command)
    }
}
