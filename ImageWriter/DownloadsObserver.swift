//
//  DownloadsObserver.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation

class DownloadsObserver : NSObject, NSFilePresenter {
    lazy var presentedItemOperationQueue = OperationQueue.main
    var presentedItemURL: URL?
    
    private let delegate: DownloadsObserverDelegate
    
    init(withDelegate delegate: DownloadsObserverDelegate, downloadsFolder: URL) {
        self.presentedItemURL = downloadsFolder
        self.delegate = delegate
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    
    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }
    
    func presentedSubitemDidChange(at url: URL) {
        if (["img", "iso"].contains(url.pathExtension)) {
            self.delegate.onDownloadsChanged()
        }
    }
}

protocol DownloadsObserverDelegate {
    func onDownloadsChanged()
}
