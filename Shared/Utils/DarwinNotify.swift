import Foundation
import os.log

/// Darwin Notify 跨进程通知
/// 用于主 App 和键盘扩展之间的即时状态同步
enum DarwinNotify {
    
    // MARK: - Notification Names
    
    /// 录音状态变化通知
    static let recordingStateChanged = "com.cover.CoKeyboard.recordingStateChanged" as CFString
    
    /// 处理状态变化通知
    static let processingStateChanged = "com.cover.CoKeyboard.processingStateChanged" as CFString
    
    // 用于内部转发的 NotificationCenter 名称
    static let internalNotificationName = Notification.Name("DarwinNotifyReceived")
    
    // MARK: - Post Notification
    
    /// 发送跨进程通知
    /// - Parameter name: 通知名称
    static func post(_ name: CFString) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name), nil, nil, true)
        logInfo("Darwin notify posted: \(name)")
    }
    
    // MARK: - Observe Notification
    
    /// 监听跨进程通知
    /// - Parameters:
    ///   - name: 通知名称
    ///   - callback: 回调闭包
    static func observe(_ name: CFString, callback: @escaping () -> Void) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let nameString = name as String
        
        // 使用 NotificationCenter 转发，避免 C 函数指针问题
        NotificationCenter.default.addObserver(
            forName: Notification.Name("darwin.\(nameString)"),
            object: nil,
            queue: .main
        ) { _ in
            callback()
        }
        
        // 注册 Darwin 通知监听
        CFNotificationCenterAddObserver(
            center,
            nil,
            darwinNotifyCallback,
            name,
            nil,
            .deliverImmediately
        )
        logInfo("Darwin notify observer added for: \(name)")
    }
    
    /// 移除通知监听
    /// - Parameter name: 通知名称
    static func removeObserver(_ name: CFString) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveObserver(center, nil, CFNotificationName(name), nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("darwin.\(name as String)"), object: nil)
        logInfo("Darwin notify observer removed for: \(name)")
    }
    
    // MARK: - Private
    
    private static let notifyLog = OSLog(subsystem: "com.cokeyboard", category: "Notify")
    
    private static func logInfo(_ message: String) {
        os_log("📡 [Notify] %{public}@", log: notifyLog, type: .info, message)
    }
}

// C 函数回调，必须在全局作用域
private func darwinNotifyCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let name = name else { return }
    let nameString = name.rawValue as String
    // 通过 NotificationCenter 转发到主线程
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: Notification.Name("darwin.\(nameString)"), object: nil)
    }
}
