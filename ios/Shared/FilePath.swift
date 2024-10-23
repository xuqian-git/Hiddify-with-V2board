//
//  FilePath.swift
//  SingBoxPacketTunnel
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation

public enum FilePath {
    public static let packageName = {
        Bundle.main.infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String ?? "unknown"
    }()
}

public extension FilePath {
    static let groupName = "group.\(packageName)"

//    private static let defaultSharedDirectory: URL! = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)

    
    private static let defaultSharedDirectory: URL! = {
        print(FilePath.groupName)
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FilePath.groupName)
        
        if let directory = directory {
            print("Shared directory: \(directory)")
        } else {
            print("Failed to retrieve shared directory for group: \(FilePath.groupName)")
        }

        return directory
    }()
    
    
    static let sharedDirectory = defaultSharedDirectory!

    static let cacheDirectory = sharedDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
