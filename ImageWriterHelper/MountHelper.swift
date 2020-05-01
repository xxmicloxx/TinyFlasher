//
//  MountHelper.swift
//  com.xxmicloxx.ImageWriterHelper
//
//  Created by Michael Loy on 23.04.20.
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation

class DiskHelper {
    private var success = false
    private var dispatchGroup = DispatchGroup()
    private var preventMountDisk: String? = nil
    private var daSession: DASession
    
    init() {
        daSession = DASessionCreate(kCFAllocatorDefault)!
        DASessionSetDispatchQueue(daSession, DispatchQueue.main)
    }
    
    private static let claimCallback:
        @convention(c) (DADisk, DADissenter?, UnsafeMutableRawPointer?) -> Void = { disk, dissenter, ptr in
            let mySelf = Unmanaged<DiskHelper>.fromOpaque(ptr!).takeUnretainedValue()
            mySelf.success = dissenter == nil
            mySelf.dispatchGroup.leave()
    }
    
    private static let unmountCallback:
        @convention(c) (DADisk, DADissenter?, UnsafeMutableRawPointer?) -> Void = { disk, dissenter, ptr in
            let mySelf = Unmanaged<DiskHelper>.fromOpaque(ptr!).takeUnretainedValue()
            mySelf.success = dissenter == nil
            mySelf.dispatchGroup.leave()
    }
    
    private static let mountCallback:
        @convention(c) (DADisk, DADissenter?, UnsafeMutableRawPointer?) -> Void = { disk, dissenter, ptr in
            let mySelf = Unmanaged<DiskHelper>.fromOpaque(ptr!).takeUnretainedValue()
            mySelf.success = dissenter == nil
            mySelf.dispatchGroup.leave()
    }
    
    private static let mountApprovalCallback:
        @convention(c) (DADisk, UnsafeMutableRawPointer?) -> Unmanaged<DADissenter>? = { disk, ptr -> Unmanaged<DADissenter>? in
            let mySelf = Unmanaged<DiskHelper>.fromOpaque(ptr!).takeUnretainedValue()
            
            if mySelf.checkMount(disk) {
                return nil
            }
            
            let descTxt = "Writing image"
            return Unmanaged.passRetained(DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnNotPermitted), descTxt as CFString))
    }
    
    private func checkMount(_ disk: DADisk) -> Bool {
        guard let bsdPtr = DADiskGetBSDName(disk) else {
            return true
        }
        
        let bsdName = String(cString: bsdPtr)
        guard let diskBsdName = preventMountDisk else {
            return true
        }
        
        if bsdName == diskBsdName || bsdName.starts(with: diskBsdName + "s") {
            return false
        }
        
        // we need to check if we are child to the target disk
        // find the next disk
        let media = DADiskCopyIOMedia(disk)
        defer { IOObjectRelease(media) }
        var parent: io_registry_entry_t = media
        var result = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &parent)
        while result == kIOReturnSuccess {
            var classStr: String? = IOObjectCopyClass(parent).takeRetainedValue() as String
            repeat {
                if classStr == kIOMediaClass {
                    // we found a root IOMediaClass
                    // check for the root class
                    let rootDisk = DADiskCreateFromIOMedia(kCFAllocatorDefault, daSession, parent)!
                    IOObjectRelease(parent)
                    return checkMount(rootDisk)
                }
                
                classStr = IOObjectCopySuperclassForClass(classStr as CFString?)?.takeRetainedValue() as String?
            } while classStr != nil
            
            let oldParent = parent
            result = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &parent)
            IOObjectRelease(oldParent)
        }
        
        // didn't find a root
        // allow mount
        return true
    }
    
    func reset() {
        self.dispatchGroup = DispatchGroup()
        allowMount()
    }
    
    func claimDisk(_ daDisk: DADisk) -> Bool {
        self.dispatchGroup.enter()
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        DADiskClaim(daDisk, DADiskClaimOptions(kDADiskClaimOptionDefault), nil, nil, DiskHelper.claimCallback, rawSelf)
        let result = self.dispatchGroup.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(10)))
        return result == .success && self.success
    }
    
    private func preventMount(_ bsdName: String) {
        self.preventMountDisk = bsdName
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskMountApprovalCallback(daSession, nil, DiskHelper.mountApprovalCallback, rawSelf)
    }
    
    private func allowMount() {
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        let callbackPtr = unsafeBitCast(DiskHelper.mountApprovalCallback, to: UnsafeMutableRawPointer.self)
        DAUnregisterCallback(daSession, callbackPtr, rawSelf)
    }
    
    private func unmountChildren(_ media: io_registry_entry_t) -> Bool {
        let name = IORegistryEntryCopyPath(media, kIOServicePlane).takeRetainedValue() as String
        NSLog("Iterating children of %@", name)
        
        var iter = io_iterator_t()
        let retCode = IORegistryEntryGetChildIterator(media, kIOServicePlane, &iter)
        if retCode != kIOReturnSuccess {
            // just give up and continue
            return true
        }
        
        defer { IOObjectRelease(iter) }
        
        var mediaDevices = [io_registry_entry_t]()
        var otherEntries = [io_registry_entry_t]()
        
        var obj: io_registry_entry_t = IOIteratorNext(iter)
        while obj != 0 {
            var classStr: String? = IOObjectCopyClass(obj)?.takeRetainedValue() as String?
            while classStr != nil {
                if classStr == kIOMediaClass {
                    // we found a IOMediaClass
                    mediaDevices.append(obj)
                    break
                }
                
                classStr = IOObjectCopySuperclassForClass(classStr as CFString?)?.takeRetainedValue() as String?
            }
            
            if classStr == nil {
                // not an IOMedia class
                otherEntries.append(obj)
            }
            
            obj = IOIteratorNext(iter)
        }
        
        var globalSuccess = true
        
        for dev in mediaDevices {
            let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, daSession, dev)!
            let params = DADiskCopyDescription(disk) as! Dictionary<CFString, AnyObject>
            
            var success: Bool
            if params[kDADiskDescriptionMediaWholeKey]! as! Bool == true {
                success = unmountDisk(disk)
            } else {
                success = unmountChildren(dev)
            }
            
            if !success {
                globalSuccess = false
            }
            
            IOObjectRelease(dev)
        }
        
        for dev in otherEntries {
            let success = unmountChildren(dev)
            if !success {
                globalSuccess = false
            }
            
            IOObjectRelease(dev)
        }
        
        return globalSuccess
    }
    
    private func unmountDisk(_ daDisk: DADisk) -> Bool {
        // unmount child disks
        let media = DADiskCopyIOMedia(daDisk)
        defer { IOObjectRelease(media) }
        
        let bsdNamePtr = DADiskGetBSDName(daDisk)!
        let bsdName = String(cString: bsdNamePtr)
        NSLog("Unmounting %@", bsdName)
        
        let success = unmountChildren(media)
        if !success {
            NSLog("Cancelled unmounting %@", bsdName)
            return false
        }
        
        NSLog("Actually unmounting %@", bsdName)
        
        self.dispatchGroup.enter()
        let unmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionForce | kDADiskUnmountOptionWhole)
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        DADiskUnmount(daDisk, unmountOptions, DiskHelper.unmountCallback, rawSelf)
        let result = self.dispatchGroup.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(10)))
        return result == .success && self.success
    }
    
    private func remountChildren(_ media: io_registry_entry_t) {
        let name = IORegistryEntryCopyPath(media, kIOServicePlane).takeRetainedValue() as String
        NSLog("Iterating children of %@", name)
        
        var iter = io_iterator_t()
        let retCode = IORegistryEntryGetChildIterator(media, kIOServicePlane, &iter)
        if retCode != kIOReturnSuccess {
            // just give up and continue
            return
        }
        
        defer { IOObjectRelease(iter) }
        
        var mediaDevices = [io_registry_entry_t]()
        var otherEntries = [io_registry_entry_t]()
        
        var obj: io_registry_entry_t = IOIteratorNext(iter)
        while obj != 0 {
            var classStr: String? = IOObjectCopyClass(obj)?.takeRetainedValue() as String?
            while classStr != nil {
                if classStr == kIOMediaClass {
                    // we found a IOMediaClass
                    mediaDevices.append(obj)
                    break
                }
                
                classStr = IOObjectCopySuperclassForClass(classStr as CFString?)?.takeRetainedValue() as String?
            }
            
            if classStr == nil {
                // not an IOMedia class
                otherEntries.append(obj)
            }
            
            obj = IOIteratorNext(iter)
        }
    
        
        for dev in mediaDevices {
            let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, daSession, dev)!
            let params = DADiskCopyDescription(disk) as! Dictionary<CFString, AnyObject>
            
            if params[kDADiskDescriptionMediaWholeKey]! as! Bool == true {
                remountDisk(disk)
            } else {
                remountChildren(dev)
            }
            
            IOObjectRelease(dev)
        }
        
        for dev in otherEntries {
            remountChildren(dev)
            IOObjectRelease(dev)
        }
    }
    
    private func remountDisk(_ daDisk: DADisk) {
        // mount
        let bsdPtr = DADiskGetBSDName(daDisk)!
        let bsdStr = String(cString: bsdPtr)
        NSLog("Remounting %@", bsdStr)
        
        self.dispatchGroup.enter()
        let mountOptions = DADiskMountOptions(kDADiskMountOptionWhole)
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        DADiskMount(daDisk, nil, mountOptions, DiskHelper.mountCallback, rawSelf)
        let _ = self.dispatchGroup.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.seconds(10)))
        
        // remount children
        let media = DADiskCopyIOMedia(daDisk)
        defer { IOObjectRelease(media) }
        
        remountChildren(media)
    }
}
