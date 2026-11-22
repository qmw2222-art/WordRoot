# 词根地图 · WordRoot

词根地图是一款面向中文零基础成人的 100 天 iPhone 英语课程。第 1 天从喝水的 `drink` 起步，第 2 天学习表示帮助的 `help`。课程随后从日常交流延伸到旅行和其他生活场景。当前源码版本为 **1.0（构建 29）**。

打开「课程」，点「跟我学第一课」。先听完整单词、看中文意思，再把它拆开记。例如 `portable` 是「便携的」，`port` 表示携带，`-able` 表示能够。点某一部分的喇叭，会先听到完整单词，再听到这个词里刚刚亮起的那段原声。学完后可以一眼看全这个词族，再听单词、选中文意思。答错的词会在本轮再出现，到期卡会回到首页。

- 100 天从日常生活逐步进入旅行和其他表达。63 个词族与 850 个常用词穿插教学，按词义标识合并后一共 1,335 个学习条目。
- 学习页顶部保留本课词根及其读音。点音标旁的喇叭就能留在当前页听发音，还可以展开中文近音和重音提示。
- 英文单词、词根、例句和卡片统一使用 Heart 美式女声，普通话讲解使用晓晓。两种朗读都能离线播放。
- 学习记录在本机保存，支持导入和导出备份。

## 免费课程与开通方式

第 1–10 天的课程和对应词族可以随时免费学习。进入第 11 天或学习后续的新词族时，可以选择月订阅（人民币 6 元）、年订阅（26 元）或永久买断（48 元）。三种方案都能学习全部 100 天。月订阅和年订阅自动续期，永久买断只付一次。已学词的到期听音卡可继续在课程首页复习。

在「设置 → 课程与购买」可以恢复购买或管理订阅。仓库中的 StoreKit 配置用于在 Xcode 本地测试这三种方案。正式销售需在 App Store Connect 配置并审核商品，购买页显示当前商店返回的价格。

## 从源码运行

使用装有 iOS 模拟器的 Xcode 和 [Git LFS](https://git-lfs.com/)。最低部署目标为 iOS 17。已验证的开发环境为 Xcode 27.0。

```sh
git lfs install
git clone https://github.com/qmw2222-art/WordRoot.git
cd WordRoot
git lfs pull
open WordRoot.xcodeproj
```

在 Xcode 选择 **WordRoot** 和一个 iPhone 模拟器，按 **⌘R**。首次构建时 Swift Package Manager 会获取锁定版本的 SwiftFSRS。按 **⌘U** 可运行 UI 测试。在自己的 iPhone 上运行时，在 Signing & Capabilities 选择自己的开发团队，并调整 App 与测试目标的 Bundle Identifier。

从 Git LFS 拉取离线音库后即可运行课程。当前课程音库包含整词、例句和老师讲解，以及从本词原声提取的 739 段构词示范。仓库保留了早期社区录音及其署名。需要重新生成课程音频时，参见[课程朗读工具](Tools/render_lesson_audio.py)。

## 许可

项目代码采用 MIT 许可，850 常用词数据文件采用 CC BY-SA 4.0。每条真人录音保留各自的署名和许可。[代码许可](LICENSE) · [资源署名与许可](WordRoot/Content/ThirdPartyNotices.txt) · [逐条录音出处](WordRoot/Content/word-audio-credits.json)
