# 词根地图 · WordRoot

面向中文零基础成人的 iPhone 英语课程。当前公开版本为 **1.0（构建 16）**。打开「课程」，点「跟我学第一课」，先听一个整词的美式读音，弄懂中文意思，再看词里的每一块怎样帮你记住它。

第一天从 `port`（带、运）出发。`ex-` 表示向外，货物往国外运，`export` 就是「出口」。沿着同一个词根，可以继续认识 `import`、`transport` 和 `portable`。进入一课就能看到当天要学的英文和中文。学完第一组，8 个词和中文释义排在同一屏；点词可以查看音标并听发音，再点下方按钮开始 8 张听音卡。每张只播当前单词，默认选中文意思，也可以切换到选英文。答错的词会在本轮再出现，到期的卡片会回到课程首页。

- 100 天从日常生活逐步进入旅行和其他表达。63 个词族与 850 个常用词穿插教学，按词义标识合并后一共 1,335 个学习条目。
- 学习页顶部保留本课词根及其读音。点音标旁的喇叭就能留在当前页听发音，还可以展开中文近音和重音提示。
- 502 条带出处的社区真人美式录音覆盖 513 个课程用法。其余 822 个用法使用 Heart 美式女声教学录音。单词、例句和中文讲解均可离线播放。
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

Git LFS 分发两个离线音库。`WordRoot/Content/LessonAudio.sqlite` 包含 6,050 段课程朗读，`WordRoot/Content/WordAudio.sqlite` 包含 502 条真人整词录音。合成课程朗读所需的模型、依赖与参数见[课程朗读工具](Tools/render_lesson_audio.py)。

## 许可

项目代码采用 MIT 许可，850 常用词数据文件采用 CC BY-SA 4.0。每条真人录音保留各自的署名和许可。[代码许可](LICENSE) · [资源署名与许可](WordRoot/Content/ThirdPartyNotices.txt) · [逐条录音出处](WordRoot/Content/word-audio-credits.json)
