import AppKit
import Foundation

// Inviting players. The invite is two links: the iCloud share link of the HealthGlance folder (players join it and
// their shortcut uploads into it) and, optionally, an iCloud link to the players' shortcut. Without a shortcut link the
// invite carries a description that the Shortcuts app (iOS 27) turns into the shortcut. Uploading is automatic once a
// player adds the "app opened" automation; iOS does not let anyone share automations, so that step stays manual.

enum Invite {
    /// The players' shortcut: names the file after the phone, so everyone can use the same shortcut.
    static func shortcutDescription(_ lang: String) -> String {
        lang == "zh" ? """
        创建一个名为「HealthGlance 上传」的快捷指令，按顺序执行以下步骤：
        1. 查找健康样本，条件：类型是步数，开始日期是今天。然后计算统计数据：总和。
        2. 查找健康样本，条件：类型是睡眠分析，结束日期是今天，值不是清醒，值不是在床上。然后获取健康样本的详细信息：时长。然后计算统计数据：总和。
        3. 查找健康样本，条件：类型是静息心率，按开始日期排序，最新的在前，限制为 1 个。
        4. 查找健康样本，条件：类型是活动能量，开始日期是今天。然后计算统计数据：总和。
        5. 获取设备详细信息：设备名称。
        6. 添加一个文本，内容只有下面四行，冒号后面放对应步骤的结果：
        步数: 第 1 步的结果
        睡眠: 第 2 步的结果
        静息心率: 第 3 步的结果
        活动能量: 第 4 步的结果
        7. 存储文件：把这段文本存到 iCloud 云盘里的「HealthGlance」文件夹，文件名为「health-」加上第 5 步的设备名称，再加「.txt」。不要询问存储位置。文件已存在时覆盖。
        所有日期条件都不要用「在最近 1 天」。
        """ : """
        Create a shortcut named "HealthGlance Upload" that does these steps in order:
        1. Find Health Samples where Type is Steps and Start Date is today. Then Calculate Statistics: Sum.
        2. Find Health Samples where Type is Sleep Analysis, End Date is today, Value is not Awake and Value is not In Bed. Then Get Details of Health Sample: Duration. Then Calculate Statistics: Sum.
        3. Find Health Samples where Type is Resting Heart Rate, sorted by Start Date with the latest first, limited to 1 sample.
        4. Find Health Samples where Type is Active Energy and Start Date is today. Then Calculate Statistics: Sum.
        5. Get Device Details: Device Name.
        6. Make a Text with exactly these four lines, putting each result after its colon:
        steps: the result of step 1
        sleep: the result of step 2
        resting heart rate: the result of step 3
        active energy: the result of step 4
        7. Save File: save the text into the "HealthGlance" folder in iCloud Drive, named "health-" followed by the device name from step 5 and ".txt". Do not ask where to save. Overwrite the file if it exists.
        Do not use "in the last 1 day" for any date filter.
        """
    }

    static func message(_ cfg: Config, lang: String? = nil) -> String {
        let lang = lang ?? cfg.language
        let zh = lang == "zh"
        let game = cfg.gameMode == "garden" ? (zh ? "菜园" : "Garden") : (zh ? "团团对战" : "Puff Battles")
        let page = cfg.gameMode == "garden" ? "garden.html" : "pets.html"
        let folder = cfg.inviteFolderLink.isEmpty ? (zh ? "（主持人还没填文件夹链接）" : "(the host has not added the folder link yet)") : cfg.inviteFolderLink
        let shortcut = cfg.inviteShortcutLink.isEmpty
            ? (zh ? "在「快捷指令」App 里点「+」，粘贴下面这段描述，自动生成快捷指令（需要 iOS 27）：\n\n" : "In the Shortcuts app, tap + and paste this description to build the shortcut (iOS 27):\n\n") + shortcutDescription(lang) + "\n"
            : (zh ? "打开这个链接，添加快捷指令：" : "Open this link to add the shortcut: ") + cfg.inviteShortcutLink
        if zh {
            return """
            来一起玩 HealthGlance \(game)！每天的步数、睡眠和心率会让你的角色成长，大家每天自动比拼。

            1. 打开这个链接，加入共享文件夹：\(folder)
            2. \(shortcut)
            3. 手动运行一次这个快捷指令，允许它读取健康数据。
            4. 打开「快捷指令」App 的「自动化」，点「+」，选「App」，选一个你每天都会打开的 App（比如微信），选「已打开」和「立即运行」，再选这个快捷指令。之后每天打开那个 App 时，数据就会自动上传。

            你的名字取自手机名称（设置 › 通用 › 关于本机 › 名称），例如「小林的iPhone」会显示为「小林」。
            比赛页面在 iCloud 云盘 › HealthGlance › \(page)，用「文件」App 打开就能看。
            共享文件夹里的每个人都能看到大家每天的数字。生成游戏页面时，不会把这些数字发给 AI。
            """
        }
        return """
        Come play HealthGlance \(game)! Your daily steps, sleep and heart rate grow your character, and everyone competes automatically each day.

        1. Open this link to join the shared folder: \(folder)
        2. \(shortcut)
        3. Run the shortcut once by hand and allow it to read your Health data.
        4. In the Shortcuts app, open Automation, tap +, choose App, pick an app you open every day, choose Is Opened and Run Immediately, then select the shortcut. From then on, your numbers upload whenever you open that app.

        Your name comes from your phone's name (Settings › General › About › Name): "Lin's iPhone" shows as "Lin".
        The game page is in iCloud Drive › HealthGlance › \(page); open it in the Files app.
        Everyone in the shared folder can see everyone's daily numbers. Making the game page does not send them to any AI.
        """
    }

    /// Create the shared folder in iCloud Drive if needed and show it in Finder, ready to share.
    static func revealFolder() {
        let dir = Garden.sharedFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
