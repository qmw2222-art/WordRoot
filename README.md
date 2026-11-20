# 词根地图 · WordRoot

面向中文零基础成人的 iPhone 英语课程。打开「课程」从第 1 天开始，先听一个整词的美式读音，弄懂中文意思，再看词里的每一块怎样帮你记住它。

第一天从 `port`（带、运）出发。`ex-` 表示向外，货物往国外运，`export` 就是「出口」。沿着同一个词根，可以继续认识 `import`、`transport` 和 `portable`。学完一个词族，会看到完整的词义清单，随后可以听发音选英文单词或中文意思。忘掉的词会在本轮再出现，到期的卡片会回到课程首页。

- 100 天从日常生活逐步进入旅行和其他表达。63 个词族与 850 个常用词穿插教学，按词义标识合并后一共 1,335 个学习条目。
- 英文默认 Heart 美式女声。音标旁可以点读，单词、例句与中文讲解使用随包离线录音。
- 学习记录在本机保存，支持导入和导出备份。

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

`WordRoot/Content/LessonAudio.sqlite` 包含 6,015 条离线录音。通过 Git LFS 克隆可取得完整音包。需要自行生成时，课程朗读工具 [render_lesson_audio.py](Tools/render_lesson_audio.py) 列出了所需模型、依赖与参数。

## 许可

项目代码使用 [MIT 许可证](LICENSE)。850 常用词数据文件按 CC BY-SA 4.0 提供。词表版本、发音数据、复习算法和语音的来源收录于[资源署名与许可](WordRoot/Content/ThirdPartyNotices.txt)。
