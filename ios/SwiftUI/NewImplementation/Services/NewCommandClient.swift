import Combine
import Libcore

public class NewCommandClient: NSObject {
    public enum ConnectionType {
        case status
        case groups
        case log
    }
    
    private let type: ConnectionType
    private var client: LibboxCommandClient?
    
    // Combine 发布者
    public let statusPublisher = PassthroughSubject<ServiceStatus, Never>()
    public let logPublisher = PassthroughSubject<String, Never>()
    public let groupsPublisher = PassthroughSubject<[NodeGroup], Never>()
    
    init(connectionType: ConnectionType) {
        self.type = connectionType
        super.init()
    }
    
    public func connect() {
        let options = LibboxCommandClientOptions()
        switch type {
        case .status:
            options.command = LibboxCommandStatus
            options.statusInterval = 2_000_000_000 // 2秒间隔
        case .groups:
            options.command = LibboxCommandGroup
        case .log:
            options.command = LibboxCommandLog
        }
        
        client = LibboxNewCommandClient(ClientHandler(self), options)
        
        Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try self.client?.connect()
                    }
                }
            } catch {
                print("Connection failed: \(error)")
            }
        }
    }
    
    public func disconnect() {
        try? client?.disconnect()
    }
    
    private class ClientHandler: NSObject, LibboxCommandClientHandlerProtocol {
        private weak var client: NewCommandClient?
        
        init(_ client: NewCommandClient) {
            self.client = client
        }
        
        func connected() {
            print("Command client connected")
        }
        
        func disconnected(_ message: String?) {
            print("Disconnected: \(message ?? "")")
        }
        
        func writeLog(_ message: String?) {
            guard let message else { return }
            client?.logPublisher.send(message)
        }
        
        func writeStatus(_ message: LibboxStatusMessage?) {
            guard let msg = message else { return }
            let status = ServiceStatus(
                connections: msg.connections,
                memory: msg.memory,
                trafficIn: msg.trafficIn,
                trafficOut: msg.trafficOut
            )
            client?.statusPublisher.send(status)
        }
        
        func writeGroups(_ iterator: LibboxOutboundGroupIteratorProtocol?) {
            var groups = [NodeGroup]()
            while iterator?.hasNext() ?? false {
                guard let group = iterator?.next() else { continue }
                
                var items = [NodeItem]()
                let itemIterator = group.getItems()
                while itemIterator?.hasNext() ?? false {
                    guard let item = itemIterator?.next() else { continue }
                    items.append(NodeItem(
                        tag: item.tag,
                        type: item.type,
                        latency: Int(item.urlTestDelay)
                    ))
                }
                
                groups.append(NodeGroup(
                    tag: group.tag,
                    type: group.type,
                    selected: group.selected,
                    items: items
                ))
            }
            client?.groupsPublisher.send(groups)
        }
        
        func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
        func updateClashMode(_ newMode: String?) {}
    }
}

public struct ServiceStatus {
    public let connections: Int64
    public let memory: Int64
    public let trafficIn: Int64
    public let trafficOut: Int64
}

public struct NodeGroup {
    public let tag: String
    public let type: String
    public let selected: String
    public let items: [NodeItem]
}

public struct NodeItem {
    public let tag: String
    public let type: String 
    public let latency: Int
}
