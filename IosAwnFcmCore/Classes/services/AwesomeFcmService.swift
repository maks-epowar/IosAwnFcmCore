//
//  FCMService.swift
//  awesome_notifications_fcm
//
//  Created by Rafael Setragni on 04/06/21.
//

import Foundation
import IosAwnCore

open class AwesomeFcmService {
    static let TAG = "AwesomeFcmService"
    var contentInProgress:UNMutableNotificationContent?
    
    static var pushInterceptor:PushNotificationInterceptor?
    
    public init(){}
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        if let interceptor = AwesomeFcmService.pushInterceptor {
            interceptor.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }
    
    public func didReceiveRemoteNotification(
        userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) -> Bool {
        var contentInProgress = UNMutableNotificationContent()
        self.contentInProgress = contentInProgress
        let start = DispatchTime.now()
        return executeRemoteInstructions(
            userInfo: userInfo,
            contentInProgress: &contentInProgress) { success, _, error in
                if success {
                    completionHandler(.newData)
                } else if error == nil {
                    completionHandler(.noData)
                } else {
                    completionHandler(.failed)
                }
                
                let end = DispatchTime.now()
                let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)
                let timeInterval:Double = Double(nanoTime) / 1_000_000_000 // Technically could overflow for long running tests
                Logger.shared.d(AwesomeFcmService.TAG, "Push notification finished in \(timeInterval.rounded())ms")
            }
    }
    
    public static func setPushNotificationInterceptor(_ interceptor: PushNotificationInterceptor?) {
        AwesomeFcmService.pushInterceptor = interceptor
    }
    
    public func executeRemoteInstructions(
        userInfo: [AnyHashable : Any],
        contentInProgress: inout UNMutableNotificationContent,
        executeCompletion: @escaping (Bool, UNMutableNotificationContent?, Error?) -> ()
    ) -> Bool {
        var modifiedUserInfo = userInfo
        
        let notificationId: Int
        if let messageIdString = getMessageIdInString(userInfo: userInfo),
           let intValue = Int(messageIdString) {
            notificationId = intValue
        } else {
            notificationId = -1
        }
        
        var dontCallFlutter = false
        for (key, value) in modifiedUserInfo {
            guard let stringKey = key as? String else {
                continue
            }
            
            if stringKey.hasPrefix("google.") || stringKey.hasPrefix("gcm.") {
                modifiedUserInfo.removeValue(forKey: key)
                continue
            }
            
            do {
                switch key as? String {
                case FcmDefinitions.RPC_DISMISS,
                    FcmDefinitions.RPC_DISMISS_BY_ID:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try dismissNotifications(values)
                    break

                case FcmDefinitions.RPC_DISMISS_BY_CHANNEL:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try dismissNotificationsByChannel(values)
                    break

                case FcmDefinitions.RPC_DISMISS_BY_GROUP:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try dismissNotificationsByGroup(values)
                    break

                case FcmDefinitions.RPC_DISMISS_ALL:
                    if let shouldDismissAll = value as? String {
                        if shouldDismissAll == "true" {
                            try dismissAllNotifications()
                        }
                        break
                    }
                    if let shouldDismissAll = value as? Bool{
                        if shouldDismissAll {
                            try dismissAllNotifications()
                        }
                        break
                    }
                    break
                    
                case FcmDefinitions.RPC_CANCEL_SCHEDULE:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try cancelSchedules(values)
                    break

                case FcmDefinitions.RPC_CANCEL_SCHEDULE_BY_CHANNEL:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try cancelSchedulesByChannel(values)
                    break

                case FcmDefinitions.RPC_CANCEL_SCHEDULE_BY_GROUP:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try cancelSchedulesByGroup(values)
                    break

                case FcmDefinitions.RPC_CANCEL_ALL_SCHEDULES:
                    if let shouldDismissAll = value as? String {
                        if shouldDismissAll == "true" {
                            try cancelAllSchedules()
                        }
                        break
                    }
                    if let shouldDismissAll = value as? Bool{
                        if shouldDismissAll {
                            try cancelAllSchedules()
                        }
                        break
                    }
                    break
                    
                case FcmDefinitions.RPC_CANCEL_NOTIFICATION:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try cancelNotifications(values)
                    break

                case FcmDefinitions.RPC_CANCEL_NOTIFICATION_BY_CHANNEL:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try cancelNotificationsByChannel(values)
                    break

                case FcmDefinitions.RPC_CANCEL_NOTIFICATION_BY_GROUP:
                    guard let values = MapUtils<[String]>.extractStringListFromValue(value)
                    else {continue}
                    try cancelNotificationsByGroup(values)
                    break

                case FcmDefinitions.RPC_CANCEL_ALL_NOTIFICATIONS:
                    if let shouldDismissAll = value as? String {
                        if shouldDismissAll == "true" {
                            try cancelAllNotifications()
                        }
                        break
                    }
                    if let shouldDismissAll = value as? Bool{
                        if shouldDismissAll {
                            try cancelAllNotifications()
                        }
                        break
                    }
                    break
                    
                case FcmDefinitions.RPC_STOP:
                    if let shouldStop = value as? String {
                        dontCallFlutter = shouldStop == "true"
                        break
                    }
                    if let shouldStop = value as? Bool{
                        dontCallFlutter = shouldStop
                        break
                    }
                    break

                default:
                    break
                }
            } catch {
                continue
            }
        }
        
        do {
            return try processPushContent(
                userInfo: modifiedUserInfo,
                notificationId: notificationId,
                contentInProgress: &contentInProgress,
                shouldStopIfSilent: dontCallFlutter,
                interceptor: AwesomeFcmService.pushInterceptor,
                completion: executeCompletion
            )
        } catch {
            if error is AwesomeNotificationsException {
                executeCompletion(false, contentInProgress, error)
                return false
            }
            
            executeCompletion(
                false,
                contentInProgress,
                ExceptionFactory
                    .shared
                    .createNewAwesomeException(
                        className: AwesomeFcmService.TAG,
                        code: ExceptionCode.CODE_INVALID_ARGUMENTS,
                        message: "AwesomeFcmService failed to receive push content",
                        detailedCode: ExceptionCode.DETAILED_INVALID_ARGUMENTS + ".processPushContent.invalid"))
            return false
        }
    }
    
    func processPushContent(
        userInfo: [AnyHashable : Any],
        notificationId: Int,
        contentInProgress: inout UNMutableNotificationContent,
        shouldStopIfSilent: Bool,
        interceptor: PushNotificationInterceptor?,
        completion: @escaping (Bool, UNMutableNotificationContent?, Error?) -> ()
    ) throws -> Bool {
        var userInfo:[AnyHashable : Any] = userInfo
        
        // Check for interception
        if let interceptor = interceptor {
            if let interceptedUserInfo = interceptor.intercept(userInfo: userInfo) {
                // Successfully intercepted and modified userInfo
                userInfo = interceptedUserInfo
            } else {
                // Interceptor decided to stop processing, handle as needed and returning .NoData
                completion(false, contentInProgress, nil)
                return false
            }
            if userInfo.isEmpty {
                // Interceptor decided to stop processing, handle as needed and returning .NewData
                completion(true, contentInProgress, nil)
                return false
            }
        }
        
        if isNotification(userInfo: userInfo) {
            return try deliveryAwesomeNotifications(
                userInfo: userInfo,
                notificationId: notificationId,
                contentInProgress: &contentInProgress,
                completion: completion
            )
        } else {
            if shouldStopIfSilent {
                completion(true, contentInProgress, nil)
            } else {
                completion(try handleSilentData(
                    userInfo: userInfo,
                    source: FcmSource.ReceiveRemote
                ), contentInProgress, nil)
            }
            return true
        }
    }
    
    func isNotification(userInfo: [AnyHashable : Any]) -> Bool {
        let aps = userInfo["aps"] as? [String: AnyObject]
        return aps?["content-available"] as? Int != 1
    }
    
    func deliveryAwesomeNotifications(
        userInfo: [AnyHashable : Any],
        notificationId: Int,
        contentInProgress: inout UNMutableNotificationContent,
        completion: @escaping (Bool, UNMutableNotificationContent?, Error?) -> ()
    ) throws -> Bool {
        
        AwesomeNotifications.awesomeExtensions?.loadExternalExtensions()
        DefaultsManager.shared.checkIfAppGroupConnected()
        let initialLifeCycle:NotificationLifeCycle = LifeCycleManager.shared.currentLifeCycle
        
        guard var notification:NotificationModel = try buildNotificationFrom(userInfo: userInfo)
        else {
            throw ExceptionFactory
                    .shared
                    .createNewAwesomeException(
                        className: AwesomeFcmService.TAG,
                        code: FcmExceptionCode.CODE_FCM_EXCEPTION,
                        message: "Push notification content is invalid",
                        detailedCode: FcmExceptionCode.DETAILED_FCM_EXCEPTION+".deliveryAwesomeNotifications")
        }
        
        notification.content?.createdLifeCycle = initialLifeCycle
        notification.content?.displayedLifeCycle = initialLifeCycle
        contentInProgress.userInfo[Definitions.NOTIFICATION_MODEL_CONTENT] = notification.toMap()
        
        validateWatermark(notification: &notification, contentInProgress: &contentInProgress)
        
        if (userInfo["gcm.n.noui"] as? Bool) ?? false { return true }
        
        try NotificationSenderAndScheduler.send(
            createdSource: NotificationSource.Firebase,
            notificationModel: notification,
            content: contentInProgress,
            completion: completion,
            appLifeCycle: LifeCycleManager.shared.currentLifeCycle)
        return true
    }
    
    func validateWatermark(
        notification:inout NotificationModel,
        contentInProgress: inout UNMutableNotificationContent
    ) {
        var isLicenseKeyValid = false
        do {
            isLicenseKeyValid = try LicenseManager.shared.isLicenseKeyValid()
        }
        catch {
            if !(error is AwesomeNotificationsException) {
                ExceptionFactory
                    .shared
                    .registerNewAwesomeException(
                        className: AwesomeFcmService.TAG,
                        code: ExceptionCode.CODE_INVALID_ARGUMENTS,
                        message: "AwesomeFcmService received a invalid license key",
                        detailedCode: ExceptionCode.DETAILED_INVALID_ARGUMENTS + ".isLicenseKeyValid.invalid")
            }
        }
        if isLicenseKeyValid { return }
        
        contentInProgress.title = notification.content?.title ?? contentInProgress.title
        contentInProgress.body = notification.content?.body ?? contentInProgress.body
        
        if !StringUtils.shared.isNullOrEmpty(contentInProgress.title) {
            contentInProgress.title = "[DEMO] \(contentInProgress.title)"
            notification.content?.title = contentInProgress.title
        } else {
            if !StringUtils.shared.isNullOrEmpty(contentInProgress.body) {
                contentInProgress.body = "[DEMO] \(contentInProgress.body)"
                notification.content?.body = contentInProgress.body
            }
        }
    }
    
    func getMessageIdInString(userInfo: [AnyHashable : Any]) -> String?{
        if let notificationId:String = userInfo["gcm.message_id"] as? String {
            Logger.shared.d(AwesomeFcmService.TAG, "Received Firebase message id: "+(notificationId))
            return notificationId
        }
        return nil
    }
    
    func buildNotificationFrom(userInfo: [AnyHashable : Any]) throws -> NotificationModel? {
        let standardNotificationContent:[String:Any] = receiveStandardNotification(userInfo: userInfo)
        
        var awesomeContent:[String:Any] = userInfo[Definitions.NOTIFICATION_MODEL_CONTENT] != nil
                ? receiveAwesomeNotificationContent(userInfo: userInfo)
                : JsonFlattener.shared.decode(flatMap: userInfo)
        
        if let awesomeIos = awesomeContent[Definitions.NOTIFICATION_MODEL_IOS] as? [String:Any] {
            awesomeContent = MapUtils<[String:Any]>
                .deepMerge(awesomeContent, awesomeIos) as [String : Any]
        }
        
        awesomeContent = MapUtils<[String:Any]>
            .deepMerge(standardNotificationContent, awesomeContent) as [String : Any]
        let notification = NotificationModel(fromMap: awesomeContent)
        
        if notification?.content != nil && notification!.content!.channelKey == nil {
            let channelList:[NotificationChannelModel] = ChannelManager.shared.listChannels()
            notification!.content!.channelKey = channelList.first?.channelKey ?? "Miscellaneous"
        }
        return notification
    }
    
    func receiveStandardNotification(userInfo: [AnyHashable : Any]) -> [String:Any]{
        var map:[String:Any] = [:]
        if let aps = userInfo["aps"] as? Dictionary<String, AnyObject> {
            if let alert = aps["alert"]  as? Dictionary<String, AnyObject> {
                if let title = alert["title"] as? String {
                    map[Definitions.NOTIFICATION_TITLE] = title
                }
                if let body = alert["body"] as? String {
                    map[Definitions.NOTIFICATION_BODY] = body
                }
            }
            if let badge = aps["badge"] as? Int {
                map[Definitions.NOTIFICATION_BADGE] = badge
            }
            if let locKey = aps["title-loc-key"] as? String {
                map[Definitions.NOTIFICATION_TITLE_KEY] = locKey
            }
            if let locKey = aps["loc-key"] as? String {
                map[Definitions.NOTIFICATION_BODY_KEY] = locKey
            }
            if let locArgs = aps["title-loc-args"] as? [String] {
                map[Definitions.NOTIFICATION_TITLE_ARGS] = locArgs
            }
            if let locArgs = aps["loc-args"] as? [String] {
                map[Definitions.NOTIFICATION_BODY_ARGS] = locArgs
            }
        }
        
        if let options = userInfo["fcm_options"] as? NSDictionary {
            if let image = options["image"] as? String {
                map[Definitions.NOTIFICATION_LAYOUT] = "BigPicture"
                map[Definitions.NOTIFICATION_BIG_PICTURE] = image
            }
        }
        return map.isEmpty ? map : [Definitions.NOTIFICATION_MODEL_CONTENT: map]
    }
    
    func receiveAwesomeNotificationContent(userInfo: [AnyHashable : Any]) -> [String:Any]{
        var mapData:[String:Any] = [:]
        
        mapData[Definitions.NOTIFICATION_MODEL_CONTENT]  = JsonUtils.fromJson(userInfo[Definitions.NOTIFICATION_MODEL_CONTENT] as? String)
        mapData[Definitions.NOTIFICATION_MODEL_SCHEDULE] = JsonUtils.fromJson(userInfo[Definitions.NOTIFICATION_MODEL_SCHEDULE] as? String)
        mapData[Definitions.NOTIFICATION_MODEL_BUTTONS]  = JsonUtils.fromJsonArr(userInfo[Definitions.NOTIFICATION_MODEL_BUTTONS] as? String)
        mapData[Definitions.NOTIFICATION_MODEL_LOCALIZATIONS]  = JsonUtils.fromJson(userInfo[Definitions.NOTIFICATION_MODEL_LOCALIZATIONS] as? String)
        mapData[Definitions.NOTIFICATION_MODEL_IOS]  = JsonUtils.fromJson(userInfo[Definitions.NOTIFICATION_MODEL_IOS] as? String)
        
        return mapData
    }
    
    func handleSilentData(
        userInfo: [AnyHashable : Any],
        source: FcmSource
    ) throws -> Bool {
        let initialLifeCycle:NotificationLifeCycle =
                LifeCycleManager
                    .shared
                    .currentLifeCycle
        
        Logger.shared.d(AwesomeFcmService.TAG, "Received silent Firebase push")
        
        guard let dataMap:[String:Any?] = userInfo as? [String:Any?] else {
            throw ExceptionFactory
                    .shared
                    .createNewAwesomeException(
                        className: AwesomeFcmService.TAG,
                        code: FcmExceptionCode.CODE_FCM_EXCEPTION,
                        message: "UserInfo could not be converted into data map",
                        detailedCode: FcmExceptionCode.DETAILED_FCM_EXCEPTION+".handleSilentData.userInfo")
        }
        
        guard let silentData:SilentDataModel = SilentDataModel(fromMap: dataMap)
        else {
            throw ExceptionFactory
                    .shared
                    .createNewAwesomeException(
                        className: AwesomeFcmService.TAG,
                        code: ExceptionCode.CODE_INVALID_ARGUMENTS,
                        message: "AwesomeFcmService received a invalid silent data content",
                        detailedCode: ExceptionCode.DETAILED_INVALID_ARGUMENTS + ".handleSilentData.invalid")
        }
        
        silentData.registerCreationEvent(
                createdSource: .Firebase,
                createdLifeCycle: initialLifeCycle)
        
        return try FcmBroadcastSender
            .shared
            .SendBroadcastSilentData(silentData: silentData) { success, error in
                if success { return }
                if error is AwesomeNotificationsException { return }
                ExceptionFactory
                    .shared
                    .registerNewAwesomeException(
                        className: AwesomeFcmService.TAG,
                        code: ExceptionCode.CODE_INVALID_ARGUMENTS,
                        message: "AwesomeFcmService couldnt broadcast silent data content",
                        detailedCode: ExceptionCode.DETAILED_INVALID_ARGUMENTS + ".SendBroadcastSilentData.unavailable")
            }
    }
    
    func handleRemoteWillExpire() -> UNNotificationContent {
        return contentInProgress ?? UNMutableNotificationContent()
    }
    
    func dismissNotifications(_ identifiers: [String]) throws {
        identifiers.forEach { identifier in
            if let id:Int = Int(identifier) {
                let success:Bool =
                        CancellationManager
                            .shared
                            .dismissNotification(byId: id)
                
                if success && AwesomeNotifications.debug {
                    Logger.shared.d(AwesomeFcmService.TAG, "Notification id \(id) dismissed")
                }
            }
        }
    }
    func dismissNotificationsByChannel(_ channels: [String]) throws {
        channels.forEach { channel in
            let success:Bool =
            CancellationManager
                .shared
                .dismissNotifications(byChannelKey: channel)
            
            if success && AwesomeNotifications.debug {
                Logger.shared.d(AwesomeFcmService.TAG, "Notifications dismissed by channel \(channel)")
            }
        }
    }
    func dismissNotificationsByGroup(_ groups: [String]) throws {
        groups.forEach { group in
            let success:Bool =
            CancellationManager
                .shared
                .dismissNotifications(byGroupKey: group)
            
            if success && AwesomeNotifications.debug {
                Logger.shared.d(AwesomeFcmService.TAG, "Notifications dismissed by group \(group)")
            }
        }
    }
    func dismissAllNotifications() throws {
        let success:Bool =
                CancellationManager
                    .shared
                    .dismissAllNotifications()
        
        if success && AwesomeNotifications.debug {
            Logger.shared.d(AwesomeFcmService.TAG, "All notifications was dismissed")
        }
    }
    
    
    func cancelSchedules(_ identifiers: [String]) throws {
        identifiers.forEach { identifier in
            if let id:Int = Int(identifier) {
                let success:Bool =
                        CancellationManager
                            .shared
                            .cancelSchedule(byId: id)
                
                if success && AwesomeNotifications.debug {
                    Logger.shared.d(AwesomeFcmService.TAG, "Schedule id \(id) cancelled")
                }
            }
        }
    }
    func cancelSchedulesByChannel(_ channels: [String]) throws {
        channels.forEach { channel in
            let success:Bool =
            CancellationManager
                .shared
                .cancelSchedules(byChannelKey: channel)
            
            if success && AwesomeNotifications.debug {
                Logger.shared.d(AwesomeFcmService.TAG, "Schedules cancelled by channel \(channel)")
            }
        }
    }
    func cancelSchedulesByGroup(_ groups: [String]) throws {
        groups.forEach { group in
            let success:Bool =
            CancellationManager
                .shared
                .cancelSchedules(byGroupKey: group)
            
            if success && AwesomeNotifications.debug {
                Logger.shared.d(AwesomeFcmService.TAG, "Schedules cancelled by group \(group)")
            }
        }
    }
    func cancelAllSchedules() throws {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelAllSchedules()
        
        if success && AwesomeNotifications.debug {
            Logger.shared.d(AwesomeFcmService.TAG, "All schedules was cancelled")
        }
    }
    
    
    func cancelNotifications(_ identifiers: [String]) throws {
        identifiers.forEach { identifier in
            if let id:Int = Int(identifier) {
                let success:Bool =
                        CancellationManager
                            .shared
                            .cancelNotification(byId: id)
                
                if success && AwesomeNotifications.debug {
                    Logger.shared.d(AwesomeFcmService.TAG, "Notification id \(id) cancelled")
                }
            }
        }
    }
    func cancelNotificationsByChannel(_ channels: [String]) throws {
        channels.forEach { channel in
            let success:Bool =
            CancellationManager
                .shared
                .cancelNotifications(byChannelKey: channel)
            
            if success && AwesomeNotifications.debug {
                Logger.shared.d(AwesomeFcmService.TAG, "Notifications cancelled by channel \(channel)")
            }
        }
    }
    func cancelNotificationsByGroup(_ groups: [String]) throws {
        groups.forEach { group in
            let success:Bool =
            CancellationManager
                .shared
                .cancelNotifications(byGroupKey: group)
            
            if success && AwesomeNotifications.debug {
                Logger.shared.d(AwesomeFcmService.TAG, "Notifications cancelled by group \(group)")
            }
        }
    }
    func cancelAllNotifications() throws {
        let success:Bool =
                CancellationManager
                    .shared
                    .cancelAllNotifications()
        
        if success && AwesomeNotifications.debug {
            Logger.shared.d(AwesomeFcmService.TAG, "All notifications was cancelled")
        }
    }
}
