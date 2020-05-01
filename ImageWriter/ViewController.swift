//
//  ViewController.swift
//  ImageWriter
//
//  Created by Michael Loy on 19.04.20.
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Cocoa
import SecurityFoundation


class ViewController: NSViewController, DeviceEnumeratorDelegate, AppProtocol, DownloadsObserverDelegate {
    
    private var downloadsObserver: DownloadsObserver!
    private var devEnumerator: DeviceEnumerator!
    private(set) var helperConnection: HelperConnection? = nil

    private var currentFile: URL? = nil {
        didSet {
            resetImageMenu()
            updateUIState()
            
            checkWindowsImage()
        }
    }
    
    private(set) var flashing: Bool = false {
        didSet {
            updateUIState()
        }
    }
    
    private var ejecting: Bool = false {
        didSet {
            updateUIState()
        }
    }

    @IBOutlet weak var showInternalBox: NSButton!
    @IBOutlet weak var driveMenu: NSMenu!
    @IBOutlet weak var driveDropDown: NSPopUpButton!
    @IBOutlet weak var imageMenu: NSMenu!
    @IBOutlet weak var imageDropDown: NSPopUpButton!
    @IBOutlet weak var writeButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var driveLabel: NSTextField!
    @IBOutlet weak var writeModeDropDown: NSPopUpButton!
    @IBOutlet var advancedOptionsConstraint: NSLayoutConstraint!
    @IBOutlet weak var advancedOptionsDisclosure: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.setFrameSize(view.fittingSize)

        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.viewController = self
        }
        
        initHelperConnection()
        
        resetImageMenu()
        
        guard let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            else { return }
        
        downloadsObserver = DownloadsObserver(withDelegate: self, downloadsFolder: downloadsUrl)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        initEnumerator()
    }
    
    override func viewWillDisappear() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.viewController = nil
        }
    }
    
    private func initHelperConnection() {
        connectToHelper(completed: {
            do {
                let auth = try HelperConnection.getAuthSerialized()
                self.helperConnection?.getAPI()?.subscribe(withAuth: auth, flashing: { flashing in
                    DispatchQueue.main.async {
                        self.flashing = flashing
                    }
                })
            } catch {
                print("No auth :(")
            }
        })
    }
    
    private func checkWindowsImage() {
        guard let file = currentFile else {
            return
        }
        
        if IOUtil.detectMicrosoftImage(file) {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Windows image detected"
            alert.informativeText =
            """
            The selected image seems to be a windows image.
            Do you want to switch to the windows installer creation mode?
            """
            alert.addButton(withTitle: "Switch Mode")
            alert.addButton(withTitle: "Cancel")
            
            alert.beginSheetModal(for: view.window!, completionHandler: { resp in
                switch (resp) {
                case .alertFirstButtonReturn:
                    self.writeModeDropDown.selectItem(withTag: 1)
                    
                    if self.advancedOptionsDisclosure.state != .on {
                        self.advancedOptionsDisclosure.performClick(self)
                    }
                    
                    self.updateUIState()
                    
                    break
                    
                case .alertSecondButtonReturn:
                    // just close
                    break
                    
                default:
                    break
                }
            })
        }
    }
    
    private func updateUIState() {
        let working = flashing || ejecting
        
        driveDropDown.isEnabled = !working
        showInternalBox.isEnabled = !working
        imageDropDown.isEnabled = !working
        cancelButton.isEnabled = flashing
        writeButton.isEnabled = currentFile != nil && !working
        progressBar.isHidden = !working
        statusLabel.isHidden = !working
        driveLabel.isEnabled = !working && writeModeDropDown.selectedItem?.tag == 1
        writeModeDropDown.isEnabled = !working
        
        if ejecting {
            progressBar.isIndeterminate = true
            progressBar.startAnimation(self)
            statusLabel.stringValue = "Ejecting..."
        }
        
        if working {
            view.window?.styleMask.remove(.closable)
        } else {
            view.window?.styleMask.insert(.closable)
            
            progressBar.stopAnimation(self)
            progressBar.isIndeterminate = false
            progressBar.toolTip = nil
            progressBar.doubleValue = 0.0
        }
    }
    
    @IBAction func onAdvancedOptionsToggled(_ sender: NSButton) {
        // prevent arrow from bugging out
        DispatchQueue.main.async {
            self.view.layoutSubtreeIfNeeded()
            
            let oldSize = self.view.fittingSize
            self.advancedOptionsConstraint.isActive = sender.state == .off
            self.view.layoutSubtreeIfNeeded()
            let newSize = self.view.fittingSize
            
            let delta = newSize.height - oldSize.height
            var frame = self.view.window!.frame
            frame.size.height += delta
            frame.origin.y -= delta
            self.view.window!.setFrame(frame, display: true, animate: true)
        }
    }
    
    @IBAction func onWriteModeChanged(_ sender: Any) {
        updateUIState()
    }
    
    func onDownloadsChanged() {
        resetImageMenu()
    }

    private func resetImageMenu() {
        imageMenu.removeAllItems()

        if let file = currentFile {
            addFileItem(file)
        } else {
            imageMenu.addItem(withTitle: "No image selected", action: nil, keyEquivalent: "")
        }

        addDownloadImages()

        imageMenu.addItem(NSMenuItem.separator())
        imageMenu.addItem(withTitle: "Select image file...",
                action: #selector(selectImage), keyEquivalent: "")
    }

    private func addDownloadImages() {
        do {
            guard let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    else { return }

            var files = try FileManager.default.contentsOfDirectory(
                    at: downloadsUrl,
                    includingPropertiesForKeys: [.fileSizeKey, .nameKey, .creationDateKey],
                    options: [
                        .skipsSubdirectoryDescendants,
                        .skipsHiddenFiles
                    ])

            try files.sort(by: { (in1, in2) -> Bool in
                let in1Props = try in1.resourceValues(forKeys: [.creationDateKey])
                let in2Props = try in2.resourceValues(forKeys: [.creationDateKey])
                return in1Props.creationDate! >= in2Props.creationDate!
            })

            let filteredFiles = files.filter { ["img", "iso"].contains($0.pathExtension.lowercased()) }
            
            for file in filteredFiles.prefix(5) {
                let resources = try file.resourceValues(forKeys: [.fileSizeKey, .nameKey])
                let displayFileSize = ViewController.userFriendlySize(Int64(resources.fileSize!))
                let displayString = "\(resources.name!) (\(displayFileSize))"
                let item = NSMenuItem(title: displayString, action: #selector(changeImage), keyEquivalent: "")
                item.representedObject = file
                imageMenu.addItem(item)
            }
        } catch {
            // fail gracefully
            print("Could not get files in downloads dir", error)
        }
    }

    private func addFileItem(_ file: URL) {
        do {
            let resources = try file.resourceValues(forKeys: [.fileSizeKey, .nameKey])
            let displayFileSize = ViewController.userFriendlySize(Int64(resources.fileSize!))
            let displayString = "\(resources.name!) (\(displayFileSize))"
            imageMenu.addItem(withTitle: displayString, action: nil, keyEquivalent: "")
        } catch {
            // fuu
            DispatchQueue.main.async {
                self.currentFile = nil

                let alert = NSAlert(error: error)
                alert.beginSheetModal(for: self.view.window!)
            }
        }
    }

    private func initEnumerator() {
        do {
            devEnumerator = try DeviceEnumerator(withDelegate: self)
            driveDropDown.isEnabled = true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not load drive enumerator"
            alert.informativeText = """
                                    There was an error starting the drive enumerator.
                                    This could be caused by a permissions problem.
                                    """

            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Retry")

            alert.beginSheetModal(for: view.window!, completionHandler: { (resp: NSApplication.ModalResponse) in
                switch (resp) {
                case .alertFirstButtonReturn:
                    // quit app
                    NSApplication.shared.terminate(self)
                    break;

                case .alertSecondButtonReturn:
                    // retry
                    self.initEnumerator()
                    break;

                default:
                    break;
                }
            })
        }
    }

    @objc private func changeImage(_ item: NSMenuItem) {
        currentFile = (item.representedObject as! URL)
    }

    @objc private func selectImage() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Select"

        let allowedTypes = ["img", "iso"]
        openPanel.allowedFileTypes = allowedTypes
        openPanel.allowsOtherFileTypes = true
        openPanel.canDownloadUbiquitousContents = true

        openPanel.beginSheetModal(for: view.window!, completionHandler: { (resp) in
            if resp != .OK {
                return
            }

            // get the file
            guard let url = openPanel.url else {
                return
            }

            self.currentFile = url
        })
    }

    private static func userFriendlySize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }

    func deviceAppeared(_ device: DeviceEnumerator.Device) {
        let item = NSMenuItem()
        let size = ViewController.userFriendlySize(device.size)
        item.title = "\(device.name) (\(size), \(device.bsdName))"
        item.representedObject = device
        driveMenu.addItem(item)
        checkDrivesEmpty()
    }

    func deviceDisappeared(_ device: DeviceEnumerator.Device) {
        guard let idx = driveMenu.items.firstIndex(where: { (item: NSMenuItem) -> Bool in
            (item.representedObject as! DeviceEnumerator.Device) == device
        }) else {
            return
        }

        driveMenu.items.remove(at: idx)
        checkDrivesEmpty()
    }

    func clearDevices() {
        driveMenu.removeAllItems()
        checkDrivesEmpty()
    }

    private func checkDrivesEmpty() {
        let items = driveMenu.numberOfItems
        if (items == 0) {
            let item = NSMenuItem()
            item.title = "No drives found"
            item.isEnabled = false
            item.tag = 1
            driveMenu.addItem(item)
            driveDropDown.isEnabled = false
        } else if (driveMenu.numberOfItems > 1 && driveMenu.indexOfItem(withTag: 1) != -1) {
            driveMenu.removeItem(at: driveMenu.indexOfItem(withTag: 1))
            driveDropDown.isEnabled = true
        }
    }

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    private func connectToHelper(completed: @escaping () -> Void) {
        if let _ = self.helperConnection {
            completed()
            return
        }
        
        self.helperConnection = HelperConnection(proto: self)
        completed()
    }

    @IBAction func onShowInternalChanged(_ sender: Any) {
        devEnumerator.removableOnly = showInternalBox.state == .off
    }

    private func checkImageSize() -> Bool {
        guard let device = driveDropDown.selectedItem?.representedObject as? DeviceEnumerator.Device else {
            return false
        }
        
        guard let image = currentFile else {
            return false
        }
        
        let resources: URLResourceValues
        do {
            resources = try image.resourceValues(forKeys: [.fileSizeKey])
        } catch {
            // skip size check
            return true
        }
        
        if device.size < Int64(resources.fileSize!) {
            // disk too small
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Target drive too small"
            alert.informativeText = "The image file is larger than the selected target drive."
            alert.beginSheetModal(for: view.window!, completionHandler: nil)
            return false
        }
        
        return true
    }
    
    @IBAction func onWriteClicked(_ sender: Any) {
        if !checkImageSize() {
            return
        }
        
        guard let driveName = driveDropDown.selectedItem?.title else {
            return
        }
        
        // show confirm dialog
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "All files will be deleted"
        alert.informativeText =
        """
        The drive \"\(driveName)\" will be wiped completely.
        This operation cannot be undone. Are you sure?
        """
        alert.addButton(withTitle: "Wipe")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Russian Roulette")
        
        alert.beginSheetModal(for: view.window!, completionHandler: { response in
            switch response {
            case .alertFirstButtonReturn:
                self.startFlash()
                break
            case .alertSecondButtonReturn:
                // do nothing, the user chickened out
                break
            case .alertThirdButtonReturn:
                let bang = Int.random(in: 0..<6) == 0
                if (bang) {
                    self.startFlash()
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Click."
                    alert.addButton(withTitle: "Phew.")
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                }
                break
            default:
                break
            }
        })
    }
    
    private func startFlash() {
        // get disk
        guard let drive = self.driveDropDown.selectedItem?.representedObject as? DeviceEnumerator.Device else {
            // no
            return
        }
        
        // get file
        guard let url = self.currentFile else {
            return
        }
        
        let auth: [Int8]
        do {
            auth = try HelperConnection.getAuthSerialized()
        } catch {
            print("No auth :(")
            return
        }
        
        let finishHandler: (Bool) -> Void = { success in
            DispatchQueue.main.async {
                if !success {
                    self.permissionError()
                    return
                }
                
                self.flashing = true
            }
        }
        
        let tag = self.writeModeDropDown.selectedTag()
        
        if tag == 0 {
            self.helperConnection?.getAPI()?.writeImage(url, toBSDDisk: drive.bsdName, withAuth: auth, started: finishHandler)
        } else if tag == 1 {
            var label = driveLabel.stringValue
            if label.isEmpty {
                label = driveLabel.placeholderString ?? "WInstaller"
            }
            
            self.helperConnection?.getAPI()?
                .writeWindowsImage(url, toBSDDisk: drive.bsdName, withLabel: label, withAuth: auth, started: finishHandler)
        }
    }

    @IBAction func onCancelClicked(_ sender: Any) {
        do {
            let auth = try HelperConnection.getAuthSerialized()
            self.helperConnection?.getAPI()?.cancelWrite(withAuth: auth, stopped: { success in
                DispatchQueue.main.async {
                    if !success {
                        self.permissionError()
                        return
                    }
                }
            })
        } catch {
            print("Not authorized :(")
        }
    }
    
    private func permissionError() {
        // show error dialog
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Administrator privileges required"
        alert.informativeText = "You do not have the permission to perform this action. Please log in as an administrator."
        alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
    }
    
    func updateProgress(percentage: Float) {
        DispatchQueue.main.async {
            if !percentage.isNaN {
                self.progressBar.stopAnimation(self)
                self.progressBar.isIndeterminate = false
                self.progressBar.doubleValue = Double(percentage)
            } else {
                self.progressBar.isIndeterminate = true
                self.progressBar.startAnimation(self)
            }
        }
    }
    
    func updateStatus(status: String) {
        DispatchQueue.main.async {
            self.progressBar.toolTip = status
            self.statusLabel.stringValue = status
        }
    }
    
    private func eject() {
        guard let device = self.driveDropDown.selectedItem?.representedObject as? DeviceEnumerator.Device else {
            return
        }
        
        self.ejecting = true
    
        do {
            let auth = try HelperConnection.getAuthSerialized()
            self.helperConnection?.getAPI()?.eject(bsdDisk: device.bsdName, withAuth: auth, whenDone: { _ in
                DispatchQueue.main.async {
                    self.ejecting = false
                    
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = "Drive ejected successfully"
                    alert.informativeText = "The target can now be safely removed."
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Quit")
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                        switch response {
                        case .alertFirstButtonReturn:
                            // nothing
                            break
                            
                        case .alertSecondButtonReturn:
                            NSApp.terminate(self)
                            break
                            
                        default:
                            break
                        }
                    })
                }
            })
        } catch {
            // Don't care
        }
    }
    
    func writingFinsihed() {
        DispatchQueue.main.async {
            self.flashing = false
            
            let device = self.driveDropDown.selectedItem?.representedObject as? DeviceEnumerator.Device
            
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Image written successfully"
            alert.informativeText = "The image has successfully been written to the selected drive."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Quit")
            if device != nil {
                alert.addButton(withTitle: "Eject Drive")
            }
            alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                switch response {
                case .alertFirstButtonReturn:
                    // do nothing
                    break
                case .alertSecondButtonReturn:
                    // quit
                    NSApp.terminate(self)
                    break
                
                case .alertThirdButtonReturn:
                    self.eject()
                    break
                
                default:
                    break
                }
            })
        }
    }
    
    func writingError(_ error: HelperError) {
        var showDialog = true
        let msg: String
        switch error {
        case .unknownError:
            msg = "An undefined error occurred while writing the image to the target."
            break
            
        case .claimError:
            msg = "The drive could not be claimed for writing."
            break
            
        case .readError:
            msg = "The image file could not be read."
            break
            
        case .writeError:
            msg = "Writing to the target failed."
            break
            
        case .outOfSpaceError:
            msg = "The target ran out of space."
            
        case .cancelledError:
            showDialog = false
            msg = ""
            break
        }
        
        DispatchQueue.main.async {
            self.flashing = false
            
            if showDialog {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Error while writing image to drive"
                alert.informativeText = msg
                alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
            }
        }
    }
}


