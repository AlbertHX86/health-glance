# 健康小结 HealthWidget

Mac 桌面小组件：每天读取 iPhone「健康」App 的数据，用 MiniMax 生成一段中文小结，显示在桌面上。

macOS 没有「健康」App，Mac 上读不到健康数据。所以数据要先由 iPhone 的快捷指令每天导出到 iCloud 云盘。之后 Mac 上的菜单栏程序读取文件、调用 MiniMax 生成小结，再交给桌面小组件显示。

```
iPhone 快捷指令 ──写入──▶ iCloud 云盘/快捷指令/HealthWidget/health.txt
                                   │
Mac 菜单栏程序 HealthWidget ◀──读取─┘ ──调用──▶ MiniMax（OpenAI 兼容接口）
        │ 写 ~/Library/Application Support/HealthWidget/summary.json
        ▼
桌面小组件（小 / 中 / 大三种尺寸），或「在桌面固定卡片」
```

## 安装

只需要命令行工具（Command Line Tools），不需要 Xcode。

```bash
./build.sh install    # 编译、签名，安装到 ~/Applications 并启动
```

1. 点击菜单栏的心形图标，填入 MiniMax API Key，点「保存」。
2. 在桌面空白处右键，选「编辑小组件」，搜索「健康小结」，拖到桌面上。
3. 如果小组件列表里找不到，打开「在桌面固定卡片」，会显示同样的卡片，可以拖动位置。
4. 想让它常驻，打开「开机启动」。

API Key 保存在 `~/Library/Application Support/HealthWidget/config.json`，文件权限为 600。小组件运行在沙盒里，只能读 `summary.json`，不联网，也读不到 Key。

## iPhone 快捷指令（只需设置一次）

**新建快捷指令「健康导出」。**每项指标用两个动作取值：

| 指标 | 「查找健康样本」的条件 | 之后的动作 |
|---|---|---|
| 步数 | 类型 是 步数；开始日期 是今天 | 计算统计数据：总和 |
| 睡眠 | 类型 是 睡眠分析；结束日期 是今天；值 不是 清醒；值 不是 在床上 | 获取健康样本的详细信息：时长 → 计算统计数据：总和 |
| 静息心率 | 类型 是 静息心率；按开始日期排序，最新的在前；限制 1 | 不需要 |
| 活动能量 | 类型 是 活动能量；开始日期 是今天 | 计算统计数据：总和 |
| 锻炼（可选，需要 Apple Watch） | 类型 是 锻炼分钟数；开始日期 是今天 | 计算统计数据：总和 |
| 心率变异性（可选） | 类型 是 心率变异性；开始日期 是今天 | 计算统计数据：平均值 |
| 体重（可选） | 类型 是 体重；按开始日期排序，最新的在前；限制 1 | 不需要 |

不要用「在最近 1 天」：它会把昨天也算进去，步数会把昨天和今天的加在一起。用「是今天」，数字才和健康 App 的「今天」一致；睡眠用「结束日期 是今天」，取的是昨晚。

**拼成文本。**加一个「文本」动作，每行写「名称: 」，后面插入对应的变量：

```
步数: [总和]
睡眠: [总和]
静息心率: [平均值]
活动能量: [总和]
```

行名可以用中文或英文，例如「步数」「steps」。单位可写可不写，「7 小时 24 分钟」「26640 秒」「6.2 h」都能识别。

**存储文件。**加一个「存储文件」动作，关闭「询问存储位置」，目标路径填 `HealthWidget/health.txt`，打开「覆盖原有文件」。

**先手动运行一次。**第一次运行时 iPhone 会逐项询问能否读取健康数据，全部允许。自动化运行时弹不出这个询问。

**设为每天自动运行。**打开「自动化」，点「+」，选「App」，选一个你每天早上都会打开的 App（例如微信），选「已打开」，设为「立即运行」，运行「健康导出」。

为什么不定时运行：iPhone 锁屏时读不到健康数据，定时触发常会失败。打开 App 时手机一定已经解锁。

Mac 每分钟检查一次 iCloud 里的文件，数字一变就重新生成小结。你每次打开微信文件都会更新，所以自动生成最多 30 分钟一次，白天的小结会跟着步数更新。iCloud 从手机同步到 Mac 通常要几十秒到几分钟，不用手动点「立即生成」。

这些步骤是按 iOS 快捷指令的界面写的，Mac 上没法实测。各项的名称可能与你手机上略有不同。做好后，把生成的 health.txt 内容发我一次，我来核对解析是否正确。

## 测试

```bash
./build/healthwidget-cli sample/2026-10-31.txt               # 只解析
./build/healthwidget-cli sample/2026-10-31.txt --generate     # 调用 MiniMax，只打印，不写缓存
./build/healthwidget-cli --generate --save                    # 读最新数据，写入 summary.json（与程序相同）
```

不用 iPhone 也能测：把文件放进 `~/Library/Application Support/HealthWidget/inbox/`，程序同样会读取。

## 文件

| 路径 | 内容 |
|---|---|
| `Sources/Shared/Health.swift` | 文件位置、数据解析、小结和历史缓存 |
| `Sources/Shared/CardView.swift` | 卡片界面（小组件和桌面卡片共用） |
| `Sources/App/Engine.swift` | MiniMax 调用与提示词 |
| `Sources/App/App.swift` | 菜单栏程序：监视数据、生成、桌面卡片、开机启动 |
| `Sources/Widget/Widget.swift` | WidgetKit 小组件 |
| `Sources/CLI/main.swift` | 命令行测试工具 |
| `build.sh` | 编译、签名、安装 |

小结只依据导出的数据生成，不构成医疗建议。
