//
//  HelperHelper.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation
import SecurityFoundation
import ServiceManagement
import Cocoa

class HelperConnection {
    
    static var auth: AuthorizationRef? = nil
    var currentConnection: NSXPCConnection?
    private var closing: Bool = false
    
    init(proto: AppProtocol) {
        let conn = NSXPCConnection(machServiceName: HelperConstants.Identifier, options: .privileged)
        conn.exportedInterface = NSXPCInterface(with: AppProtocol.self)
        conn.exportedObject = proto
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = {
            self.currentConnection?.invalidationHandler = nil
            DispatchQueue.main.async {
                self.currentConnection = nil
            }
        }
        
        self.currentConnection = conn
        self.currentConnection?.resume()
    }
    
    func getAPI() -> HelperProtocol? {
        return self.currentConnection?.remoteObjectProxyWithErrorHandler({ error in
            if self.closing {
                print("Error while closing (this is normal): ", error)
                return
            }
            
            DispatchQueue.main.async {
                print("Fatal error on helper connection", error)
                
                let dialog = NSAlert(error: error)
                dialog.runModal()
            }
        }) as? HelperProtocol
    }
    
    func close() {
        self.closing = true
        guard let conn = self.currentConnection else { return }
        conn.invalidate()
        self.currentConnection = nil
    }
    
    static func checkHelperRecent(_ callback: @escaping (Bool) -> Void) {
        let conn = NSXPCConnection(machServiceName: HelperConstants.Identifier, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        
        var receivedVersion: String? = nil
        conn.invalidationHandler = {
            print("check version invalidate (this is corrent)")
            conn.invalidationHandler = nil
            DispatchQueue.main.async {
                callback(receivedVersion == HelperConstants.Version)
            }
        }
        conn.resume()
        
        guard let helper = conn.remoteObjectProxyWithErrorHandler({ err in
            if receivedVersion != nil {
                return
            }
            
            print("Got error while checking version", err)
            conn.invalidate()
        }) as? HelperProtocol else {
            print("Got nil as protocol while checking version")
            conn.invalidationHandler = nil
            conn.invalidate()
            callback(false)
            return
        }
        
        helper.getVersion(completion: { ver in
            print("Versiond")
            receivedVersion = ver
            if ver != HelperConstants.Version {
                // quit!
                print("Version doesn't match")
                let auth = try! HelperConnection.getAuthSerialized()
                helper.stop(withAuth: auth)
            }
            conn.invalidate()
        })
    }
    
    static func getAuthSerialized() throws -> [Int8] {
        let auth = getAuthRef()
        var authorizationExternalForm = AuthorizationExternalForm()
        let result = AuthorizationMakeExternalForm(auth, &authorizationExternalForm)
        
        if result != errAuthorizationSuccess {
            throw HelperConnectionError.unknownError
        }
        
        var tmp = authorizationExternalForm.bytes
        return withUnsafeBytes(of: &tmp, { rawPtr in
            return [Int8](rawPtr.bindMemory(to: Int8.self))
        })
    }
    
    static func blessHelper() throws {
        let auth = getAuthRef()
        try ensurePreauth(withBlessPrivileges: true)
        
        
        var cfError: Unmanaged<CFError>?
        if !SMJobBless(kSMDomainSystemLaunchd, HelperConstants.Identifier as CFString, auth, &cfError) {
            if let error = cfError?.takeRetainedValue() { throw error }
        }
    }
    
    static func dropAuth() {
        guard let ref = self.auth else {
            return
        }
        
        self.auth = nil
        AuthorizationFree(ref, [.destroyRights])
    }
    
    private static func ensurePreauth(withBlessPrivileges blessPrivileges: Bool = false) throws {
        var privileges = [String](HelperConstants.AllPermissions)
        if blessPrivileges {
            privileges.append(kSMRightBlessPrivilegedHelper)
        }
        
        try obtainPreauthPerms(privileges)
    }
    
    private static func obtainPreauthPerms(_ permissions: [String]) throws {
        let authRef = getAuthRef()
        
        let permissionArrs = permissions.map({ it in it.utf8CString })
        var authItems = [AuthorizationItem]()
        
        for perm in permissionArrs {
            // kSMRightBlessPrivilegedHelper
            let authItem: AuthorizationItem = perm.withUnsafeBufferPointer({ name -> AuthorizationItem in
                AuthorizationItem(name: name.baseAddress!, valueLength: 0, value: UnsafeMutableRawPointer(bitPattern: 0), flags: 0)
            })
            
            authItems.append(authItem)
        }
        
        try authItems.withUnsafeMutableBufferPointer({ authItemsPtr in
            var authRights: AuthorizationRights = AuthorizationRights(count: UInt32(authItemsPtr.count), items: authItemsPtr.baseAddress!)
            
            let result = withUnsafePointer(to: &authRights, { ptr in
                AuthorizationCopyRights(authRef, ptr, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            })
            
            if result != errAuthorizationSuccess {
                throw HelperConnectionError.deniedError
            }
        })
    }
    
    private static func getAuthRef() -> AuthorizationRef {
        if let ref = self.auth {
            return ref
        }
        
        let ref = createAuthRef()
        self.auth = ref
        return ref
    }
    
    private static func createAuthRef() -> AuthorizationRef {
        var authRef: AuthorizationRef?
        AuthorizationCreate(nil, nil, [], &authRef)
        return authRef!
    }
}

enum HelperConnectionError: Error {
    case deniedError
    case unknownError
    case connectionLostError
}
