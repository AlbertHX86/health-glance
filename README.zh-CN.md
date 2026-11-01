# HealthGlance 健康小结

[English](README.md) | 中文

Mac 桌面小组件。每天读取 iPhone「健康」App 的数据，用 AI 写一段简短的小结，显示在桌面上。小结会说明睡得怎么样、活动量多少、和过去 7 天比如何，再给一两条马上能做的建议。

<p>
  <img src="docs/widget-medium-zh.png" width="380" alt="中尺寸小组件">
  <img src="docs/widget-large-dark-zh.png" width="300" alt="大尺寸小组件，深色模式">
</p>

*截图里是虚构的示例数据。*界面和小结支持英文和中文，默认英文，在菜单里的「Language」切换。

## 工作原理

macOS 没有「健康」App，Mac 不能直接读取健康数据。所以由 iPhone 的快捷指令把数字导出到 iCloud 云盘，Mac 上的菜单栏程序读取后调用 MiniMax 生成小结，再交给桌面小组件显示。

```
iPhone 快捷指令 ──写入──▶ iCloud 云盘/快捷指令/HealthWidget/health.txt
                                   │
Mac 菜单栏程序 ◀──读取──────────────┘ ──调用──▶ MiniMax（OpenAI 兼容接口）
        │ 写入 ~/Library/Application Support/HealthWidget/summary.json
        ▼
桌面小组件（小 / 中 / 大三种尺寸），或固定在桌面上的卡片
```

## 需要准备

- Apple 芯片的 Mac，系统 macOS 14 Sonoma 或更新版本。
- Xcode 命令行工具，用 `xcode-select --install` 安装。不需要完整的 Xcode。
- 有健康数据的 iPhone。Apple Watch 不是必须的，但有些指标要靠它记录。
- MiniMax API Key，在 [platform.minimaxi.com](https://platform.minimaxi.com)（国内站）或 [platform.minimax.io](https://platform.minimax.io)（国际站）申请。

## 在 Mac 上安装

```bash
git clone git@github.com:AlbertHX86/health-glance.git
cd health-glance
./build.sh install    # 编译、本地签名，安装到 ~/Applications 并启动
```

1. 点菜单栏的心形图标，把「Language」切到「中文」。填入 MiniMax API Key，点「保存」。
2. 在桌面空白处右键，选「编辑小组件」，搜索「HealthGlance」，拖到桌面上。有小、中、大三种尺寸。
3. 如果小组件列表里找不到，就在菜单里打开「在桌面固定卡片」。它会用一个可拖动的窗口显示同样的卡片。
4. 想开机自动运行，打开「开机启动」。

## 设置 iPhone 快捷指令（只需一次）

**第 1 步：新建快捷指令。**在「快捷指令」App 里新建一个快捷指令，命名为「健康导出」。每项指标先加一个「查找健康样本」，按表中条件设置，再加最后一列的动作：

| 指标 | 「查找健康样本」的条件 | 之后的动作 |
|---|---|---|
| 步数 | 类型 是 步数；开始日期 是今天 | 计算统计数据：总和 |
| 睡眠 | 类型 是 睡眠分析；结束日期 是今天；值 不是 清醒；值 不是 在床上 | 获取健康样本的详细信息：时长 → 计算统计数据：总和 |
| 静息心率 | 类型 是 静息心率；按开始日期排序，最新的在前；限制 1 | 不需要 |
| 活动能量 | 类型 是 活动能量；开始日期 是今天 | 计算统计数据：总和 |
| 锻炼（可选，需要 Apple Watch） | 类型 是 锻炼分钟数；开始日期 是今天 | 计算统计数据：总和 |
| 心率变异性（可选） | 类型 是 心率变异性；开始日期 是今天 | 计算统计数据：平均值 |
| 体重（可选） | 类型 是 体重；按开始日期排序，最新的在前；限制 1 | 不需要 |

不要用「开始日期 在最近 1 天」。它会把昨天也算进去，步数就成了昨天加今天的总和。用「是今天」，数字才和健康 App 里的「今天」一致。睡眠用「结束日期 是今天」，取的是昨晚。

**第 2 步：拼成文本。**加一个「文本」动作，每项指标写一行。冒号后面插入第 1 步里对应那一步的结果：

```
步数: [统计数据]
睡眠: [统计数据]
静息心率: [健康样本]
活动能量: [统计数据]
```

行名可以用中文或英文，例如「步数」或「steps」。单位可写可不写，「7 小时 24 分钟」「26640」（秒）「6.2 h」都能识别。

**第 3 步：存储文件。**加一个「存储文件」动作。关闭「询问存储位置」，子路径填 `HealthWidget/health.txt`，打开「覆盖原有文件」。

**第 4 步：先手动运行一次。**第一次运行时，iPhone 会逐项询问能否读取健康数据，全部允许。自动化运行时弹不出这些询问，所以第一次必须手动运行。

**第 5 步：设为自动运行。**打开「自动化」，点「+」，选「App」，选一个你每天早上都会打开的 App（例如微信）。再选「已打开」和「立即运行」，然后选「健康导出」。

用打开 App 触发、不用定时触发，是因为 iPhone 锁屏时读不到健康数据，定时运行常会失败。

不同 iOS 版本的动作名称可能略有差别，找不到某个条件就跳过。

## 什么时候生成小结

Mac 每分钟检查一次 iCloud 里的文件，数字一变就重新生成小结，自动生成最多每 30 分钟一次。快捷指令每运行一次，文件就更新一次，所以小结会跟着你的一天更新。iCloud 把手机上的新文件同步到 Mac，通常要几秒到几分钟。

想马上生成，点菜单里的「立即生成」。

## 配置

设置保存在 `~/Library/Application Support/HealthWidget/config.json`。文件权限为 600，不会提交到仓库：

```json
{
  "apiKey": "<你的 MiniMax API Key>",
  "baseURL": "https://api.minimaxi.com/v1",
  "model": "MiniMax-M3.1-Flash",
  "reasoningEffort": "low",
  "language": "zh"
}
```

`language` 为 `en` 或 `zh`，菜单里的「Language」切换的就是它。用国际站时，把 `baseURL` 改成 `https://api.minimax.io/v1`。其他兼容 OpenAI 的接口和模型也可以用。环境变量 `MINIMAX_API_KEY` 会覆盖文件里的 Key，用命令行工具测试时方便。

## 隐私

- 生成小结时，当天的健康数字会发送给 MiniMax 接口。如果不希望这样，请不要使用本程序。
- 除此之外，数据不会离开 Mac。最近 30 天的数字保存在配置文件旁边的 `history.json` 里，用于和 7 天平均对比。
- 小组件运行在沙盒里，只能读取 `summary.json`。它读不到存有 Key 的配置文件，也不能联网。

## 不用 iPhone 测试

```bash
./build/healthwidget-cli sample/2026-10-31.txt               # 只解析
./build/healthwidget-cli sample/2026-10-31.txt --generate    # 同时调用 MiniMax；只打印，不写文件
./build/healthwidget-cli --generate --save                   # 读最新数据，写入 summary.json，与程序相同
```

放进 `~/Library/Application Support/HealthWidget/inbox/` 的文件也会被读取。

## 常见问题

| 现象 | 原因和解决办法 |
|---|---|
| 步数或睡眠明显偏高 | 快捷指令用了「在最近 1 天」，或者睡眠把「在床上」也算进去了。按上面表格里的条件设置。 |
| 数字比健康 App 里的高 | iPhone 和 Apple Watch 记录了同一段活动，快捷指令把两边加在了一起。睡眠可以加一个条件「来源 是 你的手表」。 |
| 小组件列表里找不到 | 用「在桌面固定卡片」。 |
| 菜单显示「还没有填 MiniMax API Key」 | 还没保存 Key。在菜单里粘贴后点「保存」。 |
| 小结一直不变 | 打开「文件」App，在 iCloud 云盘 › 快捷指令 › HealthWidget 里看 health.txt 有没有更新。 |

## 文件结构

| 路径 | 内容 |
|---|---|
| `Sources/Shared/Health.swift` | 文件位置、数据解析、小结和历史缓存 |
| `Sources/Shared/CardView.swift` | 卡片界面，小组件和桌面卡片共用 |
| `Sources/App/Engine.swift` | MiniMax 调用与提示词（英文、中文各一份） |
| `Sources/App/App.swift` | 菜单栏程序：监视数据、生成小结、桌面卡片、开机启动 |
| `Sources/Widget/Widget.swift` | WidgetKit 小组件 |
| `Sources/CLI/main.swift` | 命令行测试工具 |
| `build.sh` | 编译、签名、安装 |

小结只依据导出的数字生成，不构成医疗建议。

## 许可证

[MIT](LICENSE)
