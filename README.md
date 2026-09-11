# MacDuo

让 MacBook 的开合，变成画面逐渐对焦的过程。

MacDuo 是一个原生 macOS 菜单栏工具。它读取机盖角度，把应用画面模拟成停在指定角度的平面：打开屏幕时，画面逐渐重合、变清晰；合上时，透视与离焦逐渐加深。

模糊具有方向：**顶部更重、底部更轻**。窗口和桌面背景一起参与渐变离焦，背景保持平面。

## 功能

- **真实角度驱动**：通过 Apple HID 机盖传感器读取开合角度。
- **自定义清晰点**：在舒适的开盖位置一键校准，到达该角度后恢复原桌面。
- **底边固定的空间效果**：应用画面共用屏幕底边，可调节倾斜强度，并限制纵向拉伸。
- **渐变模糊**：从底部到顶部逐渐加重，合盖越多，离焦越强。
- **平滑开合**：短时角度插值、显示同步绘制、后台 GPU 编码，目标为稳定 60 fps。
- **菜单栏控制**：暂停、校准、预览和快捷键恢复；设置自动保存。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 运行系统 | macOS 14 或更新版本 |
| 角度感应 | 提供 Apple HID 机盖角度传感器的 MacBook；不保证所有机型均支持 |
| 画面权限 | 屏幕录制权限，用于实时取景与空间效果 |
| 源码构建 | macOS 15+、Swift 6 工具链、Xcode Command Line Tools、Python 3、OpenSSL 3 |

没有第三方 Swift 包依赖。当前只对内置显示屏应用效果；没有可用传感器时，可以通过“预览开合效果”体验。

## 构建与启动

```sh
git clone git@github.com:xvshiting/mac-duo.git
cd mac-duo

# 确认构建工具可用
swift --version
python3 --version
openssl version

# 构建本机架构的应用
./scripts/build.sh
open dist/MacDuo.app
```

构建产物位于 `dist/MacDuo.app`。签名脚本需要 OpenSSL 3；如果命令指向系统自带的 LibreSSL，可在已有 Homebrew 的环境中安装并指定：

```sh
brew install openssl@3
export PATH="$(brew --prefix openssl@3)/bin:$PATH"
./scripts/build.sh
```

也可以在 Xcode 中打开 `Package.swift` 查看或开发代码。

### 首次使用

1. 打开应用，点击 **“授权屏幕录制，启用立体效果”**，在系统设置中允许 MacDuo。
2. 返回应用，点击 **“我已授权，重新打开”**，让新进程读取授权状态。
3. 把机盖打开到希望画面完全清晰的位置，点击 **“将当前开盖位置设为清晰点”**。
4. 打开 **“启用效果”**，缓慢开合机盖观察变化，或点击 **“预览开合效果”**。
5. 调节顶部离焦强度和空间倾斜，直到效果符合自己的观看习惯。

关闭设置窗口后，应用继续在菜单栏运行。校准时以机盖自然可达的位置为准。

### 参数说明

| 参数 | 作用 |
| --- | --- |
| 清晰角度 | 画面完全清晰、移除效果层的位置；可手动设置或一键校准 |
| 顶部离焦强度 | 顶部最大模糊程度，底部始终相对更轻 |
| 空间倾斜 | 默认 28%；向左更竖直，向右纵深更强；0% 保留渐变模糊，100% 使用完整透视补偿 |

**快速恢复：**按 `Control + Option + Command + B`，立即恢复原桌面并暂停效果。设置窗口内按 `Esc` 也可暂停。

## 隐私与授权

画面仅在本机内存和 GPU 中处理，**不保存、不上传、不捕捉音频**。不使用摄像头，也不追踪眼睛位置。应用自己的窗口会被排除在取景之外，避免递归捕捉；设置窗口保持清晰。

构建脚本会在 `.local-signing/` 中生成并保留本地签名身份，供后续构建复用，减少因签名变化造成的重新授权。这个目录已被 Git 忽略，**不要提交或分享其中的私钥**。签名不会安装系统信任证书、修改登录钥匙串或隐私数据库；应用没有 Developer ID 公证。

未获得屏幕录制权限时，应用会退回普通全屏模糊；空间透视和上下渐变需要授权后才能使用。

## 已知限制

- 空间固定感由虚拟视点模拟，实际观感会受坐姿影响。较低倾斜强度和防拉伸限制会优先保证画面自然，而非完全准确的几何补偿。
- 效果层不接收鼠标或键盘，底下的应用仍在运行，但鼠标命中区域不会随显示画面变形。需要操作桌面时，打开到清晰点或先暂停效果。
- 仅处理当前可捕捉的桌面，不处理系统登录或锁定画面。打开菜单时会临时恢复原桌面。
- 主渲染使用 ScreenCaptureKit、Metal 和 Core Image。普通模糊后备路径使用私有 `CGSSetWindowBackgroundBlurRadius`，当前完整版本不适合直接提交 Mac App Store。
- 帧率随设备、分辨率和桌面负载变化；目前不自动设置开机启动。

## 测试与诊断

```sh
# 单元测试与真实 Core Image 像素回归测试
swift test

# 额外运行全分辨率 GPU 性能基准
MACDUO_BENCHMARK=1 swift test --filter RendererPerformanceTests

# 检查机盖传感器与模糊后备接口
./dist/MacDuo.app/Contents/MacOS/MacDuo --diagnose

# 通过正常应用启动路径检查取景、权限和渲染耗时
open -n dist/MacDuo.app --args --check-perspective \
  --report /tmp/macduo-capture-report.json
```

测试覆盖传感器报告、离焦曲线、角度平滑、底边固定、防拉伸、窗口与背景的渐变模糊、授权重复点击和重启行为。GPU 性能基准默认跳过，需要上述环境变量启用。

取景诊断会短暂显示效果，结束后退出；报告只包含权限、帧数、窗口数量和耗时指标，不包含桌面图像。通过已获授权的终端直接启动诊断可能继承终端权限，因此建议用上面的 `open` 命令验证应用自身授权。

其他检查：

```sh
./scripts/test-signing-identity.sh  # 构建后检查更新版本的签名身份一致性
./scripts/test-visual-blur.sh      # 检查普通模糊后备路径，需要取景权限
```

## 项目结构

```text
Sources/
  FocusCore/       角度解码、离焦曲线、透视模型、运动插值
  MacDuo/          菜单栏与设置、HID 取样、取景、渲染、权限管理
Tests/             模型、像素渲染、权限与性能测试
Resources/         应用 Info.plist
scripts/           构建、本地签名与回归检查
```

更多投影计算、签名机制和性能诊断说明见 [开发文档](docs/DEVELOPMENT.md)。

## 参考

- [Apple：ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple：按遮罩渐变模糊](https://developer.apple.com/documentation/coreimage/selectively-focusing-on-an-image)
- [Apple：MTKView](https://developer.apple.com/documentation/metalkit/mtkview)
- [LidAngle：机盖传感器](https://github.com/deepakness/LidAngle)
- [mac-angle：传感器协议](https://github.com/ufoym/mac-angle)
- [CGSInternal：WindowServer 接口](https://github.com/NUIKit/CGSInternal/blob/master/CGSWindow.h)
