//
//  HelperConstants.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation

class HelperConstants {
    @available(*, unavailable) private init() {}
    
    static let Identifier = "com.xxmicloxx.ImageWriterHelper"
    
    static let WritePermission = "com.xxmicloxx.ImageWriterHelper.write"
    static let CancelPermission = "com.xxmicloxx.ImageWriterHelper.cancel"
    static let SubscribePermission = "com.xxmicloxx.ImageWriterHelper.subscribe"
    static let StopPermission = "com.xxmicloxx.ImageWriterHelper.stop"
    static let EjectPermission = "com.xxmicloxx.ImageWriterHelper.eject"
    
    static let AllPermissions = [
        HelperConstants.WritePermission,
        HelperConstants.CancelPermission,
        HelperConstants.SubscribePermission,
        HelperConstants.StopPermission,
        HelperConstants.EjectPermission
    ]
    
    static let Version = "1.1.27"
}

@objc enum HelperError: Int {
    case unknownError
    case claimError
    case cancelledError
    case readError
    case writeError
    case outOfSpaceError
}
