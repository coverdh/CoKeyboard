import Foundation

enum AppConstants {
    static let appGroupID = "group.com.cover.CoKeyboard"
    static let defaultTargetLanguage = "English(US)"
    static let defaultVoiceBackgroundDuration = 60
    static let llmTimeoutSeconds: TimeInterval = 10
    static let llmMaxRetries = 1

    // Shared keys for App Groups
    static let pendingResultKey = "pendingVoiceResult"
    static let pendingResultTimestampKey = "pendingVoiceResultTimestamp"
    static let sourceAppURLKey = "sourceAppURL"
}

// Common app URL schemes for return navigation
enum CommonAppSchemes {
    static let schemes: [String: String] = [
        "com.apple.MobileSMS": "sms://",
        "com.apple.mobilemail": "mailto://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.apple.reminders": "x-apple-reminderkit://",
        "com.tencent.xin": "weixin://",
        "com.tencent.mqq": "mqq://",
        "com.tencent.WeChat": "weixin://",
        "com.alibaba.china.taobao": "taobao://",
        "com.alipay.iphoneclient": "alipay://",
        "com.sina.weibo": "sinaweibo://",
        "com.douban.frodo": "douban://",
        "com.zhihu.ios": "zhihu://",
        "com.ss.iphone.article.News": "snssdk141://",
        "com.ss.iphone.ugc.Aweme": "snssdk1128://",
        "com.burbn.instagram": "instagram://",
        "com.facebook.Facebook": "fb://",
        "com.twitter.twitter": "twitter://",
        "com.google.Gmail": "googlegmail://",
        "com.microsoft.Office.Outlook": "ms-outlook://",
        "com.slack.Slack": "slack://",
        "org.telegram.Telegram": "tg://",
        "ph.telegra.Telegraph": "telegram://",
        "com.skype.skype": "skype://",
        "com.discord": "discord://",
    ]
}
