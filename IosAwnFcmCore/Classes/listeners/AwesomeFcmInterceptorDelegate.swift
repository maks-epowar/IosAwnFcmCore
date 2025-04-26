//
//  AwesomeFcmInterceptorDelegate.swift
//  Pods
//
//  Created by Maks Rahman on 26/04/2025.
//

import Foundation

public protocol AwesomeFcmInterceptorDelegate: AnyObject {
    func handleRemoteNotification(userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool
}
