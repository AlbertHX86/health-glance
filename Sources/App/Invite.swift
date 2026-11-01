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
        1. 查找健康样本：类型是步数，开始日期在最近 30 天内，分组方式为「天」，关闭「填充缺失值」。
        2. 对第 1 步的每一项重复：把它的开始日期格式化为自定格式 yyyy-MM-dd，添加文本「格式化后的日期 步数: 它的数值」。
        3. 查找健康样本：类型是活动能量，开始日期在最近 30 天内，分组方式为「天」，关闭「填充缺失值」。
        4. 对第 3 步的每一项重复：把它的开始日期格式化为 yyyy-MM-dd，添加文本「格式化后的日期 活动能量: 它的数值」。
        5. 查找健康样本：类型是静息心率，开始日期在最近 30 天内，分组方式为「天」。
        6. 对第 5 步的每一项重复：把它的开始日期格式化为 yyyy-MM-dd，添加文本「格式化后的日期 静息心率: 它的数值」。
        7. 查找健康样本：类型是睡眠分析，结束日期在最近 30 天内，值不是清醒，值不是在床上，不限制数量。
        8. 对第 7 步的每一项重复：把它的结束日期格式化为自定格式 yyyy-MM-dd HH:mm，添加文本「格式化后的日期 睡眠 (它的来源): 它的时长」。
        9. 把第 2、4、6、8 步的重复结果合并成一段文本，每项一行。
        10. 获取设备详细信息：设备名称。
        11. 存储文件：存储位置选 iCloud 云盘最外层的「HealthGlance」文件夹（不是「快捷指令」文件夹里面），子路径只填文件名：「health-」加上第 10 步的设备名称，再加「.txt」。不要询问存储位置。文件已存在时覆盖。
        """ : """
        Create a shortcut named "HealthGlance Upload" that does these steps in order:
        1. Find Health Samples where Type is Steps and Start Date is in the last 30 days, grouped by Day, with Fill Missing off.
        2. Repeat with each item from step 1: format its Start Date with the custom format yyyy-MM-dd, and make a Text of the formatted date, " steps: " and its Value.
        3. Find Health Samples where Type is Active Energy and Start Date is in the last 30 days, grouped by Day, with Fill Missing off.
        4. Repeat with each item from step 3: format its Start Date as yyyy-MM-dd, and make a Text of the formatted date, " active energy: " and its Value.
        5. Find Health Samples where Type is Resting Heart Rate and Start Date is in the last 30 days, grouped by Day.
        6. Repeat with each item from step 5: format its Start Date as yyyy-MM-dd, and make a Text of the formatted date, " resting heart rate: " and its Value.
        7. Find Health Samples where Type is Sleep Analysis, End Date is in the last 30 days, Value is not Awake and Value is not In Bed, with no limit.
        8. Repeat with each item from step 7: format its End Date with the custom format yyyy-MM-dd HH:mm, and make a Text of the formatted date, " sleep (", its Source, "): " and its Duration.
        9. Combine the Repeat Results of steps 2, 4, 6 and 8 into one text, one item per line.
        10. Get Device Details: Device Name.
        11. Save File: set the destination folder to the "HealthGlance" folder at the top level of iCloud Drive (not inside the Shortcuts folder), with only the file name as the subpath: "health-" followed by the device name from step 10 and ".txt". Do not ask where to save. Overwrite the file if it exists.
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
            3. 手动运行一次这个快捷指令，允许它读取健康数据。然后打开「文件」App › iCloud 云盘 › HealthGlance，确认里面出现了 health-你的手机名.txt。如果它跑到了「快捷指令」文件夹里，就在「存储文件」里点蓝色的「快捷指令」，改选最外层的 HealthGlance。
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
        3. Run the shortcut once by hand and allow it to read your Health data. Then check in the Files app that iCloud Drive › HealthGlance has health-<your phone name>.txt. If it went into the Shortcuts folder instead, tap the blue Shortcuts folder in Save File and choose the top-level HealthGlance.
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
