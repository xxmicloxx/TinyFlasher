//
//  IOUtil.swift
//  com.xxmicloxx.ImageWriterHelper
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation
import MachO

class IOUtil {
    @available(*, unavailable) private init() {}
    
    static func loadUefiImage() -> Data? {
        if let handle = dlopen(nil, RTLD_LAZY) {
            defer { dlclose(handle) }

            if let ptr = dlsym(handle, MH_EXECUTE_SYM) {
                let mhExecHeaderPtr = ptr.assumingMemoryBound(to: mach_header_64.self)

                var size: UInt = 0
                let uefiImage = getsectiondata(
                    mhExecHeaderPtr,
                    "__DATA",
                    "__uefi_ntfs_img",
                    &size)

                guard let rawPtr = UnsafeMutableRawPointer(uefiImage) else {
                    return nil
                }
                
                let data = Data(bytes: rawPtr, count: Int(size))
                return data
            }
        }
        
        return nil
    }
    
    static func flash(data: Data, to output: URL) -> HelperError? {
        let inputFile = InputStream(data: data)
        inputFile.open()
        
        guard let diskFile = OutputStream(url: output, append: false) else {
            inputFile.close()
            return .writeError
        }
        diskFile.open()
        
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        var read = 0
        var written = 0
        repeat {
            read = inputFile.read(buffer, maxLength: bufferSize)
            
            if read < 0 {
                // error
                inputFile.close()
                diskFile.close()
                return .readError
            }
            
            if read > 0 {
                written = diskFile.write(buffer, maxLength: read)
                if written < read {
                    // error
                    inputFile.close()
                    diskFile.close()
                    if written < 0 {
                        return .writeError
                    } else {
                        return .outOfSpaceError
                    }
                }
            }
            
            if Thread.current.isCancelled {
                inputFile.close()
                diskFile.close()
                return .cancelledError
            }
        } while read > 0
        
        diskFile.close()
        inputFile.close()
        
        return nil
    }
    
    static func dd(if input: URL, of output: URL, updateStatus: ((String) -> Void)?, onProgress: (Float) -> Void) -> HelperError? {
        updateStatus?("Opening image file...")
        
        var sourceSize: Int64 = 0
        do {
            let sourceInfo = try input.resourceValues(forKeys: [.fileSizeKey])
            sourceSize = Int64(sourceInfo.fileSize ?? 0)
        } catch {
            NSLog("Could not get source file size!")
        }
        
        guard let imageFile = InputStream(url: input) else {
            return .readError
        }
        imageFile.open()
        
        updateStatus?("Opening target disk...")
        
        guard let diskFile = OutputStream(url: output, append: false) else {
            imageFile.close()
            return .writeError
        }
        diskFile.open()
        
        updateStatus?("Writing to disk...")
        onProgress(0.0)
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        
        let bufferSize = 4 * 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        var lastProgressUpdate = DispatchTime.now()
        var totalCopied: Int64 = 0
        var read = 0
        var written = 0
        repeat {
            read = imageFile.read(buffer, maxLength: bufferSize)
            if read < 0 {
                // error
                imageFile.close()
                diskFile.close()
                return .readError
            }
            
            if read > 0 {
                written = diskFile.write(buffer, maxLength: read)
                if written < read {
                    // error
                    imageFile.close()
                    diskFile.close()
                    if written < 0 {
                        return .writeError
                    } else {
                        return .outOfSpaceError
                    }
                }
            }
            
            totalCopied += Int64(read)
            
            if Thread.current.isCancelled {
                imageFile.close()
                diskFile.close()
                return .cancelledError
            }
            
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastProgressUpdate.uptimeNanoseconds > 200_000_000 && sourceSize != 0 {
                lastProgressUpdate = now
                let progess = Double(totalCopied) / Double(sourceSize)
                onProgress(Float(progess * 100.0))
                
                let copiedStr = formatter.string(fromByteCount: totalCopied)
                let totalStr = formatter.string(fromByteCount: sourceSize)
                updateStatus?("Writing to disk... (\(copiedStr) of \(totalStr))")
            }
        } while read > 0
        
        diskFile.close()
        imageFile.close()
        
        return nil
    }
    
    static func run(executable: String, withArgs args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice
        
        NSLog("Running %@ with args %@", executable, args)
        
        do {
            try proc.run()
        } catch {
            return false
        }
        
        proc.waitUntilExit()
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outData, as: UTF8.self)
        let error = String(decoding: errData, as: UTF8.self)
        
        NSLog("STDOUT: %@", output)
        NSLog("STDERR: %@", error)
        
        return proc.terminationStatus == 0
    }
    
    static func readHDIUtil(withArgs args: [String]) -> [String: AnyObject]? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice
        
        NSLog("Getting plist from hdiutil with args %@", args)
        
        do {
            try proc.run()
        } catch {
            return nil
        }
        
        proc.waitUntilExit()
        
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outData, as: UTF8.self)
        let error = String(decoding: errData, as: UTF8.self)
        
        NSLog("STDOUT: %@", output)
        NSLog("STDERR: %@", error)
        
        if proc.terminationStatus != 0 {
            return nil
        }
        
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
        do {
            guard let dict = try PropertyListSerialization.propertyList(from: outData, options: [], format: &propertyListFormat)
                as? [String : AnyObject] else {
                NSLog("Could not decode output")
                    return nil
            }
            
            return dict
        } catch {
            NSLog("Could not decode output")
            return nil
        }
    }
    
    static func copyFolderContents(from src: URL, to target: URL, totalSize: Int, updateStatus: (String) -> Void, updateProgress: (Float) -> Void) -> HelperError? {
        do {
            let sourceComponents = src.pathComponents.count
            guard let contents = FileManager.default.enumerator(at: src, includingPropertiesForKeys: [.fileSizeKey]) else {
                NSLog("Could not get source directory contents")
                return .readError
            }
            
            var alreadyCopied: Int = 0
            for obj in contents {
                let file = obj as! URL
                let components = file.pathComponents
                let missingComponents = Array(components[sourceComponents...])
                
                let vals = try file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                
                var targetFile = target
                for i in 0..<missingComponents.count {
                    let component = missingComponents[i]
                    if i < missingComponents.count-1 {
                        targetFile = targetFile.appendingPathComponent(component, isDirectory: true)
                    } else {
                        targetFile = targetFile.appendingPathComponent(component, isDirectory: vals.isDirectory == true)
                    }
                }
                
                // check if we are cancelled
                if Thread.current.isCancelled {
                    return .cancelledError
                }
                
                if vals.isDirectory == true {
                    // create directory
                    try FileManager.default.createDirectory(at: targetFile, withIntermediateDirectories: true, attributes: nil)
                    continue
                }
                
                let currentProgress = Double(alreadyCopied) / Double(totalSize) * 100.0
                updateStatus("Copying \(file.lastPathComponent)...")
                updateProgress(Float(currentProgress))
                
                if let size = vals.fileSize {
                    let percentage = Double(size) / Double(totalSize)
                    if (percentage > 0.01) {
                        // percentage copy
                        if let res = dd(if: file, of: targetFile, updateStatus: nil, onProgress: { progress in
                            let relPercentage = progress * Float(percentage)
                            updateProgress(relPercentage + Float(currentProgress))
                        }) {
                            NSLog("Got error while copying: \(res)")
                            return res
                        }
                        
                        alreadyCopied += vals.fileSize ?? 0
                        continue
                    }
                }
                
                // plain copy
                try FileManager.default.copyItem(at: file, to: targetFile)
                alreadyCopied += vals.fileSize ?? 0
            }
            
            return nil
        } catch {
            NSLog("Unknown error while copying directory: \(error)")
            return .unknownError
        }
    }
}
