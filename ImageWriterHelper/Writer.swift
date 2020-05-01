//
//  Writer.swift
//  com.xxmicloxx.ImageWriterHelper
//
//  Created by Michael Loy on 23.04.20.
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation
import IOKit.storage

enum FlashMode {
    case direct
    case windows
}

struct FlashInfo {
    var sourceImage: URL
    var targetDisk: String
    var flashMode: FlashMode
    var label: String = ""
}

class Writer {
    
    var flashing: Bool {
        get {
            return flashInfo != nil
        }
    }
    
    private let helper: Helper
    private let diskHelper: DiskHelper
    
    private var flashingThread: Thread? = nil
    private var flashInfo: FlashInfo? = nil
    
    init(withHelper helper: Helper) {
        self.helper = helper
        self.diskHelper = DiskHelper()
    }
    
    func startDirectWrite(_ imageURL: URL, toBSDDisk bsdDisk: String) {
        self.flashingThread?.cancel()
        self.flashInfo = FlashInfo(sourceImage: imageURL, targetDisk: bsdDisk, flashMode: .direct)
        self.flashingThread = Thread(target: self, selector: #selector(flashingThreadExec), object: nil)
        self.flashingThread?.start()
    }
    
    func startWindowsWrite(_ imageURL: URL, toBSDDisk bsdDisk: String, withLabel label: String) {
        self.flashingThread?.cancel()
        self.flashInfo = FlashInfo(sourceImage: imageURL, targetDisk: bsdDisk, flashMode: .windows, label: label)
        self.flashingThread = Thread(target: self, selector: #selector(flashingThreadExec), object: nil)
        self.flashingThread?.start()
    }
    
    func cancelWrite() {
        self.flashingThread?.cancel()
        cleanupWritingThread()
    }
    
    private func cleanupWritingThread() {
        self.flashingThread = nil
        self.flashInfo = nil
    }
    
    private func finishWriting() {
        cleanupWritingThread()
        self.helper.subscribedAppProtocol?.writingFinsihed()
    }
    
    private func failThread(withError error: HelperError) {
        DispatchQueue.main.async {
            self.cleanupWritingThread()
            self.helper.subscribedAppProtocol?.writingError(error)
        }
    }
    
    private func flashDirectly(toDisk daDisk: DADisk, withInfo info: FlashInfo) -> HelperError? {
        func updateStatus(_ status: String) {
            self.helper.subscribedAppProtocol?.updateStatus(status: status)
        }
        
        func updateProgress(_ progress: Float) {
            self.helper.subscribedAppProtocol?.updateProgress(percentage: progress)
        }
        
        updateStatus("Unmounting disk...")
        
        diskHelper.preventMount(info.targetDisk)
        
        if !diskHelper.unmountDisk(daDisk) {
            diskHelper.allowMount()
            return .claimError
        }
        
        // check if we are cancelled
        if Thread.current.isCancelled {
            diskHelper.allowMount()
            return .cancelledError
        }
        
        let diskUrl = URL(fileURLWithPath: "/dev/r\(info.targetDisk)")
        if let error = IOUtil.dd(if: info.sourceImage, of: diskUrl, updateStatus: updateStatus(_:), onProgress: updateProgress(_:)) {
            diskHelper.allowMount()
            return error
        }
        
        // check if we are cancelled
        if Thread.current.isCancelled {
            diskHelper.allowMount()
            return .cancelledError
        }
        
        updateProgress(Float.nan)
        updateStatus("Remounting disk...")
        
        diskHelper.allowMount()
        diskHelper.remountDisk(daDisk)
        
        return nil
    }
    
    private func flashWindowsImage(toDisk daDisk: DADisk, withInfo info: FlashInfo) -> HelperError? {
        func updateStatus(_ status: String) {
            self.helper.subscribedAppProtocol?.updateStatus(status: status)
        }
        
        func updateProgress(_ progress: Float) {
            self.helper.subscribedAppProtocol?.updateProgress(percentage: progress)
        }
        
        updateStatus("Unmounting disk...")
        
        if !diskHelper.unmountDisk(daDisk) {
            return .claimError
        }
        
        // check if we are cancelled
        if Thread.current.isCancelled {
            return .cancelledError
        }
        
        updateStatus("Partitioning disk...")
        if !IOUtil.run(executable: "/usr/sbin/diskutil", withArgs: [
            "partitionDisk", // action
            info.targetDisk, // target
            "1", // partition count (will still create hidden EFI partition, which we need)
            "GPT", // partition table type
            "ExFAT", // partition type of part 1 (actually part 2 since EFI is automatically created)
            String(info.label.prefix(11)),
            "0" // size, 0 means "fill"
        ]) {
            // error
            NSLog("Couldn't partition %@", info.targetDisk)
            return .writeError
        }
        
        // now we need to get the partition's mount point
        // partition is \(name)s2
        let partName = "\(info.targetDisk)s2"
        guard let daPart = diskHelper.createDisk(partName) else {
            NSLog("Couldn't create partition handle")
            return .claimError
        }
        
        let volumePath = diskHelper.get(property: kDADiskDescriptionVolumePathKey, ofDisk: daPart) as! URL
        NSLog("Volume path of disk: %@", volumePath.path)
        
        // check if we are cancelled
        if Thread.current.isCancelled {
            return .cancelledError
        }
        
        updateStatus("Mounting image...")
        
        // mount using hdiutil
        NSLog("Mounting image at %@", info.sourceImage.path)
        guard let attachInfo = IOUtil.readHDIUtil(withArgs: ["attach", "-plist", info.sourceImage.path]) else {
            return .readError
        }
        
        let sysEntities = attachInfo["system-entities"] as? [[String: AnyObject]]
        let entity = sysEntities?[0]
        guard let mountPoint = entity?["mount-point"] as? String else {
            NSLog("No mountpoint in output data")
            return .readError
        }
        
        NSLog("Windows image mounted at %@", mountPoint)
        let mountUrl = URL(fileURLWithPath: mountPoint)
        
        guard let imageSize = try? info.sourceImage.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            NSLog("Could not access source file for size request")
            
            let _ = IOUtil.readHDIUtil(withArgs: ["detach", mountPoint])
            return .readError
        }
        
        // check if we are cancelled
        if Thread.current.isCancelled {
            let _ = IOUtil.readHDIUtil(withArgs: ["detach", mountPoint])
            return .cancelledError
        }
        
        updateStatus("Copying files...")
        
        if let error = IOUtil.copyFolderContents(from: mountUrl, to: volumePath, totalSize: imageSize,
                                                 updateStatus: updateStatus(_:), updateProgress: updateProgress(_:)) {
            NSLog("Error copying folder contents")
            let _ = IOUtil.readHDIUtil(withArgs: ["detach", mountPoint])
            return error
        }
        
        updateStatus("Unmounting image...")
        self.helper.subscribedAppProtocol?.updateProgress(percentage: Float.nan)
        
        let _ = IOUtil.readHDIUtil(withArgs: ["detach", mountPoint])
        
        updateStatus("Flashing bootloader...")
        
        let efiUrl = URL(fileURLWithPath: "/dev/r\(info.targetDisk)s1")
        guard let efiData = IOUtil.loadUefiImage() else {
            NSLog("Couldn't load EFI image")
            return .unknownError
        }
        
        if let err = IOUtil.flash(data: efiData, to: efiUrl) {
            NSLog("Error flashing EFI")
            return err
        }
        
        return nil
    }
    
    @objc private func flashingThreadExec() {
        diskHelper.reset()
        
        guard let info = self.flashInfo else {
            self.failThread(withError: .unknownError)
            return
        }
        
        self.helper.subscribedAppProtocol?.updateProgress(percentage: Float.nan)
        self.helper.subscribedAppProtocol?.updateStatus(status: "Claiming disk...")
        guard let daDisk = diskHelper.createDisk(info.targetDisk) else {
            // failed
            self.failThread(withError: .unknownError)
            return
        }
        
        if !diskHelper.claimDisk(daDisk) {
            DADiskUnclaim(daDisk)
            self.failThread(withError: .claimError)
            return
        }
        
        let error: HelperError?
        switch (info.flashMode) {
        case .direct:
            error = flashDirectly(toDisk: daDisk, withInfo: info)
            break
            
        case .windows:
            error = flashWindowsImage(toDisk: daDisk, withInfo: info)
            break
        }
        
        if let err = error {
            DADiskUnclaim(daDisk)
            self.failThread(withError: err)
            return
        }
        
        DADiskUnclaim(daDisk)
        
        DispatchQueue.main.async {
            self.finishWriting()
        }
    }
}

