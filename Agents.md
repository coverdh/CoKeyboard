# CoKeyboard 智能语音键盘

## 项目概述

CoKeyboard 是一款 iOS 键盘扩展应用，通过语音识别技术实现语音输入功能。由于 iOS 键盘扩展无法直接使用麦克风，采用了主 App 协同架构来完成录音和语音处理。

## 用户操作流程

### 1. 语音输入流程

```
用户点击键盘语音按钮
        ↓
键盘扩展 (KeyboardViewController)
        ↓
通过 URL Scheme 打开主 App (coapp://start-recording)
        ↓
主 App (CoKeyboardApp) 开始后台录音
        ↓
用户说话...
        ↓
用户返回键盘，点击停止
        ↓
主 App 停止录音，保存音频文件
        ↓
 Whisper 转写 (WhisperService)
        ↓
(可选) LLM 润色 (PolishService)
        ↓
结果写入共享存储 (RecordingSessionManager)
        ↓
键盘读取结果，插入文本
```

### 2. 主要交互场景

#### 场景一：首次使用语音输入
1. 用户打开任意文本输入界面，切换到 CoKeyboard
2. 点击工具栏设置按钮或语音按钮
3. 主 App 打开，显示录音权限请求
4. 授权麦克风权限后，即可开始使用

#### 场景二：语音转文字
1. 用户在文本输入框中
2. 点击键盘中央的语音按钮
3. 主 App 自动启动并开始录音（带录音界面 overlay）
4. 录音完成后自动返回原 App
5. 识别的文字自动插入到光标位置

#### 场景三：翻译功能
1. 用户输入或粘贴需要翻译的文本
2. 点击工具栏翻译按钮
3. 键盘获取当前文本内容
4. 调用翻译服务 (TranslationService)
5. 替换原文本为翻译结果

## 代码结构

### App/ - 主应用模块

| 文件 | 功能 |
|------|------|
| [CoKeyboardApp.swift](App/CoKeyboardApp.swift) | 主 App 入口，处理 URL Scheme 唤起、录音界面 |
| [MainTabView.swift](App/Views/MainTabView.swift) | 主界面 Tab 导航 |
| [HistoryListView.swift](App/Views/History/HistoryListView.swift) | 输入历史列表 |
| [HistoryDetailView.swift](App/Views/History/HistoryDetailView.swift) | 历史详情 |
| [SettingsView.swift](App/Views/Settings/SettingsView.swift) | 设置主界面 |
| [LLMSettingsView.swift](App/Views/Settings/LLMSettingsView.swift) | LLM API 配置 |
| [TranslationSettingsView.swift](App/Views/Settings/TranslationSettingsView.swift) | 翻译语言设置 |
| [VocabularyView.swift](App/Views/Settings/VocabularyView.swift) | 词汇表管理 |
| [StatisticsView.swift](App/Views/Statistics/StatisticsView.swift) | 使用统计 |
| [BackgroundRecordingService.swift](App/Services/BackgroundRecordingService.swift) | 后台录音服务 |

### Keyboard/ - 键盘扩展模块

| 文件 | 功能 |
|------|------|
| [KeyboardViewController.swift](Keyboard/KeyboardViewController.swift) | 键盘主控制器，处理 UI 和交互 |
| [VoiceButton.swift](Keyboard/Views/VoiceButton.swift) | 语音按钮组件 |
| [ToolbarView.swift](Keyboard/Views/ToolbarView.swift) | 工具栏（设置、翻译、空格、删除） |
| [TokenCounterView.swift](Keyboard/Views/TokenCounterView.swift) | Token 计数器显示 |
| [VoiceInputController.swift](Keyboard/Controllers/VoiceInputController.swift) | 语音输入核心逻辑 |
| [AudioRecorder.swift](Keyboard/Controllers/AudioRecorder.swift) | 键盘端音频录制（未使用，保留） |

### Shared/ - 共享代码模块

#### 服务层 (Services/)

| 文件 | 功能 |
|------|------|
| [RecordingSessionManager.swift](Shared/Services/RecordingSessionManager.swift) | **核心**：跨进程状态管理，通过 App Group 共享数据 |
| [WhisperService.swift](Shared/Services/WhisperService.swift) | Whisper 语音转文字 |
| [TranslationService.swift](Shared/Services/TranslationService.swift) | 翻译服务 |
| [NetworkMonitor.swift](Shared/Services/NetworkMonitor.swift) | 网络状态监控 |

#### LLM 服务 (Services/LLM/)

| 文件 | 功能 |
|------|------|
| [LLMClient.swift](Shared/Services/LLM/LLMClient.swift) | LLM 客户端接口 |
| [OpenAIClient.swift](Shared/Services/LLM/OpenAIClient.swift) | OpenAI API 实现 |
| [PolishService.swift](Shared/Services/LLM/PolishService.swift) | 文本润色服务 |

#### 数据模型 (Models/)

| 文件 | 功能 |
|------|------|
| [AppSettings.swift](Shared/Models/AppSettings.swift) | 应用设置 |
| [InputRecord.swift](Shared/Models/InputRecord.swift) | 输入记录 |
| [DailyUsage.swift](Shared/Models/DailyUsage.swift) | 每日使用统计 |
| [VocabularyItem.swift](Shared/Models/VocabularyItem.swift) | 词汇表项 |

#### 存储层 (Storage/)

| 文件 | 功能 |
|------|------|
| [DataManager.swift](Shared/Storage/DataManager.swift) | SwiftData 数据管理 |

#### 工具类 (Utils/)

| 文件 | 功能 |
|------|------|
| [Constants.swift](Shared/Utils/Constants.swift) | 常量定义（App Group ID、URL Scheme 等） |
| [PermissionManager.swift](Shared/Utils/PermissionManager.swift) | 权限管理 |

## 核心机制

### App Group 跨进程通信

项目使用 App Group (`group.com.corkeyboard.shared`) 实现键盘扩展与主 App 之间的数据共享：

- **录音状态**: `isRecording`, `shouldStopRecording`, `processingStatus`
- **音频文件**: 通过共享容器存储 `recording.wav`
- **转写结果**: `pendingResult` 传递语音识别结果

### URL Scheme 唤起机制

```
coapp://start-recording?source=com.example.app
coapp://activate-session
coapp://request-mic-permission
coapp://settings
```

### 处理流程状态机

```
idle → recording → transcribing → polishing → done
                                         ↓
                                      error
```

## 依赖配置

项目使用 XcodeGen 生成 Xcode 项目，配置文件为 `project.yml`。

主要依赖（通过 Swift Package Manager）：
- OpenAI Swift SDK（用于 Whisper 和 LLM）
- 其他系统框架：AVFoundation, SwiftUI, SwiftData
