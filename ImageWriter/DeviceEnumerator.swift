//
// Created by Michael Loy on 19.04.20.
// Copyright (c) 2020 xxmicloxx. All rights reserved.
//

import Foundation
import IOKit.storage
import DiskArbitration
import CoreFoundation.CFRunLoop

class DeviceEnumerator {
    let delegate: DeviceEnumeratorDelegate

    let session: DASession
    var removableOnly: Bool = true {
        didSet {
            reattachCallbacks()
        }
    }

    private static let rawDiskAppearedCallback:
            @convention(c) (DADisk, UnsafeMutableRawPointer?) -> Void = { disk, pointer in

        let mySelf = Unmanaged<DeviceEnumerator>.fromOpaque(pointer!).takeUnretainedValue()
        mySelf.onDiskAppeared(disk)
    }

    private static let rawDiskDisappearedCallback:
            @convention(c) (DADisk, UnsafeMutableRawPointer?) -> Void = { disk, pointer in

        let mySelf = Unmanaged<DeviceEnumerator>.fromOpaque(pointer!).takeUnretainedValue()
        mySelf.onDiskDisappeared(disk)
    }
    
    init(withDelegate delegate: DeviceEnumeratorDelegate) throws {
        self.delegate = delegate

        if let session = DASessionCreate(kCFAllocatorDefault) {
            self.session = session
        } else {
            throw DeviceEnumeratorError.generalError
        }

        reattachCallbacks()

        DASessionScheduleWithRunLoop(self.session, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
    
    private func reattachCallbacks() {
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()

        let diskAppearedPtr =
                unsafeBitCast(DeviceEnumerator.rawDiskAppearedCallback, to: UnsafeMutableRawPointer.self)
        DAUnregisterCallback(self.session, diskAppearedPtr, rawSelf)

        let diskDisappearedPtr =
                unsafeBitCast(DeviceEnumerator.rawDiskDisappearedCallback, to: UnsafeMutableRawPointer.self)
        DAUnregisterCallback(self.session, diskDisappearedPtr, rawSelf)

        self.delegate.clearDevices()

        var descriptor = Dictionary<CFString, AnyObject>()
        descriptor[kDADiskDescriptionMediaWholeKey] = kCFBooleanTrue
        descriptor[kDADiskDescriptionMediaWritableKey] = kCFBooleanTrue
        if (self.removableOnly) {
            descriptor[kDADiskDescriptionMediaRemovableKey] = kCFBooleanTrue
        }

        let rawDescriptor = descriptor as CFDictionary

        DARegisterDiskAppearedCallback(self.session, rawDescriptor, DeviceEnumerator.rawDiskAppearedCallback, rawSelf)
        DARegisterDiskDisappearedCallback(self.session, rawDescriptor, DeviceEnumerator.rawDiskDisappearedCallback, rawSelf)
    }

    private func onDiskAppeared(_ disk: DADisk) {
        // check if this is APFS
        let media = DADiskCopyIOMedia(disk)
        defer { IOObjectRelease(media) }
        var parent: io_registry_entry_t = media
        var result = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &parent)
        while result == kIOReturnSuccess {
            var hadIOStorage = false
            
            var classStr: String? = IOObjectCopyClass(parent).takeRetainedValue() as String
            repeat {
                if classStr == kIOMediaClass {
                    // block it
                    let namePtr = DADiskGetBSDName(disk)!
                    let name = String(cString: namePtr)
                    print("Blocked device \(name) because it has a root device (APFS?)")
                    // this is the actual root device
                    // skip the disk
                    IOObjectRelease(parent)
                    return
                } else if classStr == kIOStorageClass {
                    hadIOStorage = true
                    break
                }
                
                classStr = IOObjectCopySuperclassForClass(classStr as CFString?)?.takeRetainedValue() as String?
            } while classStr != nil
            
            if !hadIOStorage {
                // no need to iterate further
                IOObjectRelease(parent)
                break
            }
            
            let oldParent = parent
            result = IORegistryEntryGetParentEntry(parent, kIOServicePlane, &parent)
            IOObjectRelease(oldParent)
        }
        
        self.delegate.deviceAppeared(Device(fromDisk: disk))
    }

    private func onDiskDisappeared(_ disk: DADisk) {
        self.delegate.deviceDisappeared(Device(fromDisk: disk))
    }

    struct Device : Equatable {
        init(fromDisk disk: DADisk) {
            let props = DADiskCopyDescription(disk) as! Dictionary<CFString, AnyObject>
            name = props[kDADiskDescriptionMediaNameKey] as! String
            bsdName = props[kDADiskDescriptionMediaBSDNameKey] as! String

            let cfNum = props[kDADiskDescriptionMediaSizeKey] as! CFNumber
            self.size = Int64(truncating: cfNum)
        }

        let name: String
        let bsdName: String
        let size: Int64

        static func ==(lhs: Device, rhs: Device) -> Bool {
            lhs.bsdName == rhs.bsdName
        }
    }
}

enum DeviceEnumeratorError: Error {
    case generalError
}

protocol DeviceEnumeratorDelegate {
    func deviceAppeared(_ device: DeviceEnumerator.Device)

    func deviceDisappeared(_ device: DeviceEnumerator.Device)

    func clearDevices()
}
