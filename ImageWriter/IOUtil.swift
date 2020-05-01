//
//  IOUtil.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation

class IOUtil {
    @available(*, unavailable) private init() {}
    
    static func detectMicrosoftImage(_ imageUrl: URL) -> Bool {
        let compareStr = "MICROSOFT CORPORATION"
        let compareData = compareStr.data(using: .ascii)!
        
        // load some bytes
        let handle = try? FileHandle(forReadingFrom: imageUrl)
        defer { try? handle?.close() }
        
        try? handle?.seek(toOffset: 0x813E)
        let result = handle?.readData(ofLength: compareData.count)
        return result == compareData
    }
}
