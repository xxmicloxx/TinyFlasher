//
//  AppProtocol.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation

@objc(AppProtocol)
protocol AppProtocol {
    func updateStatus(status: String)
    func updateProgress(percentage: Float)
    func writingFinsihed()
    func writingError(_ error: HelperError)
}
