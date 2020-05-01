//
//  HelperUtil.swift
//  ImageWriter
//
//  Copyright © 2020 xxmicloxx. All rights reserved.
//

import Foundation
import Security.Authorization

class HelperUtil {
    @available(*, unavailable) private init() {}
    
    static func checkAuthorization(_ authData: [Int8], forPerm perm: String) -> Bool {
        if authData.count != MemoryLayout<AuthorizationExternalForm>.size {
            // invalid
            return false
        }
        let auth = authData.withUnsafeBytes({ bytes in
            return bytes.bindMemory(to: AuthorizationExternalForm.self)[0]
        })
        
        var authRef: AuthorizationRef? = nil
        let result = withUnsafePointer(to: auth, { authFormPtr in
            AuthorizationCreateFromExternalForm(authFormPtr, &authRef)
        })
        if result != errAuthorizationSuccess {
            // error
            return false
        }
        guard let ref = authRef else {
            return false
        }
        defer {
            var freeFlags: AuthorizationFlags = [.destroyRights]
            let freeRes = AuthorizationFree(ref, freeFlags)
            assert(freeRes == errAuthorizationSuccess)
        }
        
        // we got a auth now copy rights
        let permissionArr = perm.utf8CString
        var authItem = permissionArr.withUnsafeBufferPointer({ name -> AuthorizationItem in
            AuthorizationItem(name: name.baseAddress!, valueLength: 0, value: UnsafeMutableRawPointer(bitPattern: 0), flags: 0)
        })
        
        return withUnsafeMutablePointer(to: &authItem) { ptr in
            var authRights: AuthorizationRights = AuthorizationRights(count: 1, items: ptr)
            
            let err = AuthorizationCopyRights(ref, &authRights, nil, [.extendRights, .interactionAllowed], nil)
            return err == errAuthorizationSuccess
        }
    }
}
