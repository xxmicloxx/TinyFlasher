//
//  Helper.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation
import DiskArbitration

class Helper: NSObject, NSXPCListenerDelegate, HelperProtocol {
    
    private let listener: NSXPCListener
    private var writer: Writer!
    
    private var connections = [NSXPCConnection]()
    private var shouldQuit = false
    private var subscribedConnection: NSXPCConnection? = nil
    internal var subscribedAppProtocol: AppProtocol? = nil
    
    override init() {
        self.listener = NSXPCListener(machServiceName: HelperConstants.Identifier)
        super.init()
        self.writer = Writer(withHelper: self)
        self.listener.delegate = self
    }
    
    func run() {
        self.listener.resume()
        RunLoop.current.run()
    }
    
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.remoteObjectInterface = NSXPCInterface(with: AppProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        
        connection.invalidationHandler = {
            if let connectionIndex = self.connections.firstIndex(of: connection) {
                self.connections.remove(at: connectionIndex)
            }
            
            if (self.subscribedConnection == connection) {
                self.subscribedAppProtocol = nil
                self.subscribedConnection = nil
            }
        }
        
        self.connections.append(connection)
        connection.resume()
        
        return true
    }
    
    func getVersion(completion: @escaping (String) -> Void) {
        completion(HelperConstants.Version)
    }
    
    func writeImage(_ imageURL: URL, toBSDDisk bsdDisk: String, withAuth auth: [Int8], started: @escaping (Bool) -> Void) {
        let authed = HelperUtil.checkAuthorization(auth, forPerm: HelperConstants.WritePermission)
        if !authed {
            started(false)
            return
        }
        
        if self.writer.flashing {
            started(false)
            return
        }
        
        // check url and bsddisk
        if !imageURL.isFileURL || bsdDisk.range(of: #"^disk[0-9]+$"#, options: .regularExpression) == nil {
            // parameter error
            started(false)
            return
        }
        
        self.writer.startDirectWrite(imageURL, toBSDDisk: bsdDisk)
        started(authed)
    }
    
    func writeWindowsImage(_ imageURL: URL, toBSDDisk bsdDisk: String, withLabel label: String, withAuth auth: [Int8], started: @escaping (Bool) -> Void) {
        let authed = HelperUtil.checkAuthorization(auth, forPerm: HelperConstants.WritePermission)
        if !authed {
            started(false)
            return
        }
        
        if self.writer.flashing {
            started(false)
            return
        }
        
        // check url and bsddisk
        if !imageURL.isFileURL || bsdDisk.range(of: #"^disk[0-9]+$"#, options: .regularExpression) == nil {
            // parameter error
            started(false)
            return
        }
        
        self.writer.startWindowsWrite(imageURL, toBSDDisk: bsdDisk, withLabel: label)
        started(authed)
    }
    
    func cancelWrite(withAuth auth: [Int8], stopped: @escaping (Bool) -> Void) {
        let authed = HelperUtil.checkAuthorization(auth, forPerm: HelperConstants.CancelPermission)
        if (!authed) {
            stopped(false)
        }
        self.writer.cancelWrite()
        stopped(true)
    }
    
    func stop(withAuth auth: [Int8]) {
        if !HelperUtil.checkAuthorization(auth, forPerm: HelperConstants.StopPermission) {
            return
        }
        
        self.listener.invalidate()
        exit(0)
    }
    
    func subscribe(withAuth auth: [Int8], flashing: @escaping (Bool) -> Void) {
        if !HelperUtil.checkAuthorization(auth, forPerm: HelperConstants.SubscribePermission) {
            return
        }
        
        guard let connection = NSXPCConnection.current() else {
            return
        }
        
        self.subscribedConnection = connection
        self.subscribedAppProtocol = connection.remoteObjectProxyWithErrorHandler({ error in
            NSLog("Got error %@", error as NSError)
            self.subscribedAppProtocol = nil
            self.subscribedConnection = nil
            if self.writer.flashing {
                self.writer.cancelWrite()
            }
        }) as? AppProtocol
        
        flashing(self.writer.flashing)
    }
    
    func eject(bsdDisk: String, withAuth auth: [Int8], whenDone: @escaping (Bool) -> Void) {
        if !HelperUtil.checkAuthorization(auth, forPerm: HelperConstants.EjectPermission) {
            whenDone(false)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let diskHelper = DiskHelper()
            guard let disk = diskHelper.createDisk(bsdDisk) else {
                whenDone(false)
                return
            }
            
            if !diskHelper.unmountDisk(disk) {
                whenDone(false)
                return
            }
            
            if !diskHelper.ejectDisk(disk) {
                whenDone(false)
                return
            }
            
            whenDone(true)
        }
    }
}


