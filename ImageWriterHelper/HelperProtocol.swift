//
//  HelperProtocol.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation
import Security.Authorization

@objc(HelperProtocol)
protocol HelperProtocol {
    func writeImage(_ imageURL: URL, toBSDDisk bsdDisk: String, withAuth: [Int8], started: @escaping (Bool) -> Void)
    
    func writeWindowsImage(_ imageURL: URL, toBSDDisk bsdDisk: String, withLabel: String, withAuth: [Int8], started: @escaping(Bool) -> Void)
    
    func cancelWrite(withAuth: [Int8], stopped: @escaping (Bool) -> Void)
    
    func getVersion(completion: @escaping (String) -> Void)
    
    func subscribe(withAuth: [Int8], flashing: @escaping (Bool) -> Void)
    
    func eject(bsdDisk: String, withAuth: [Int8], whenDone: @escaping (Bool) -> Void)
    
    func stop(withAuth: [Int8])
}
