//
//  AppDelegate.swift
//  ImageWriter
//
//  Created by Michael Loy on 19.04.20.
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Cocoa
import Security.AuthorizationDB
import Security.Authorization


@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var viewController: ViewController? = nil
    
    private func installRights() {
        var authRef: AuthorizationRef?
        AuthorizationCreate(nil, nil, [], &authRef)
        guard let ref = authRef else {
            print("Could not register auth!")
            return
        }
        
        for perm in HelperConstants.AllPermissions {
            var currentRule: CFDictionary?
            var status = AuthorizationRightGet(perm, &currentRule)
            if status == errAuthorizationDenied {
                // add rule
                
                let ruleString = kAuthorizationRuleIsAdmin as CFString
                let description = "ImageWriterHelper wants to write an image to a disk or manage its progress"
                status = AuthorizationRightSet(ref, perm, ruleString, description as CFString, nil, nil)
                print("Set auth rule")
            }
            
            guard status == errAuthorizationSuccess else {
                print("Couldn't set auth rule")
                continue
            }
        }
        
        AuthorizationFree(ref, [])
    }
    
    private func setupHelper(complete: @escaping () -> Void) {
        HelperConnection.checkHelperRecent({ recent in
            if !recent {
                print("Upgrading helper...")
                do {
                    try HelperConnection.blessHelper()
                } catch {
                    print("User denied access", error)
                    // show error
                    let error = NSAlert()
                    error.alertStyle = .critical
                    error.messageText = "Helper installation error"
                    error.informativeText = "The helper application could not be installed. It is required for the operation of this app."
                    error.runModal()
                    NSApp.terminate(self)
                    return
                }
            } else {
                print("No need to upgrade :)")
            }
            
            complete()
        })
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        installRights()
        setupHelper {
            // launch main app
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            let controller = storyboard.instantiateController(withIdentifier: "MainController") as! NSWindowController
            controller.showWindow(self)
        }
    }


    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = viewController else {
            return .terminateNow
        }
        
        if controller.flashing {
            NSSound.beep()
            return .terminateCancel
        }
        
        return .terminateNow
    }
    
    @IBAction func tryTerminate(_ sender: Any) {
        let shouldTerminate = applicationShouldTerminate(NSApp)
        
        if shouldTerminate == .terminateNow {
            NSApp.terminate(sender)
        }
    }
}
