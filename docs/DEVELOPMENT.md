# 实现与开发说明

## 立体效果如何工作

- `FocusPlaneTransform.swift`：应用画面固定在校准角度，屏幕底边两个角恒定不动。以相对底座固定的虚拟观察点，将目标画面的视线投射到当前机盖平面，而不是让画面绕中心缩小。观察点距铰链向用户方向 2.4 个屏幕高度、向上 0.8 个屏幕高度。为避免极端角度下拉长和翻面，会限制补偿：纵向局部放大率不超过 1，角度差最多 85°，近切线分母有下限；到清晰点投影严格恢复原尺寸。最终按“空间倾斜”强度将顶边向原位收回，底边保持固定；默认 28%，0% 为正面平面，100% 为完整补偿。
- `PerspectiveOverlay.swift`：用 ScreenCaptureKit 分别读取应用窗口层与桌面背景层，排除应用自己的全部窗口，避免递归捕捉。应用层最高 60 fps，桌面背景层 30 fps，由 MTKView 显示刷新驱动画面更新（目标稳定 60 fps，实际受屏幕与渲染耗时限制）；窗口集合变化会自动更新。暂停、睡眠、退出时停止取景；重新启用或唤醒时重连。
- `PlaneRenderer.swift`：先把透视窗口叠加到平面背景，再统一使用 `CIMaskedVariableBlur` 和由黑到白的竖直遮罩，得到底部最轻、顶部最重的真实变半径模糊；角度差决定顶部最大半径。由原先两层各自全画面模糊改为合成后一次渐变模糊，保留原生分辨率。Core Image 编码放在独立串行队列，最多两个在途帧，避免主线程被渲染阻塞和旧帧积压。
- `EffectMotion.swift`：按真实帧间隔对 30 Hz 整数角度读数做短时插值；角度时间常数 18 ms，约 55 ms 收敛到 95%，不预测、不超调。离焦时间常数 30 ms，在不同刷新率下表现一致。
- `FocusModel.swift`：用角度差对应的弦长计算离焦量，目标角度处严格为零。
- `LidSensor.swift`：后台串行队列以 30 Hz 读取 Apple HID 机盖角度 Feature Report 1，校验输入并在失联时重连。

这是基于固定虚拟视点的空间模拟，不使用摄像头或追踪眼睛位置；实际观看效果会随坐姿变化。100% 强度下，独立的底座坐标系视线测试验证清晰点 130°、机盖 90°～130° 时角点和内部标记的视线一致，并用真实渲染验证底边不退缩、内容不纵向拉长。默认较低强度优先保持画面竖直的观感，会放松精确的视线固定；触发防拉伸限制后也会牺牲部分空间固定精度，优先避免画面变形失控。几何使用短时插值抑制传感器读数步进，保持跟手；机盖停下后迅速收敛。效果期间覆盖层不接收鼠标或键盘；原应用仍在运行，但其鼠标命中区域没有随显示画面变形，正常操作应在画面重合后进行。

## 授权循环修复与本地签名

旧的 ad-hoc 签名以代码哈希作为身份，每次构建改变代码就会使旧授权不匹配。现在 `scripts/sign_app.py` 使用 `.local-signing/` 中持久保存的本地签名密钥与证书，由内存中的签名器签名；不会安装系统信任证书，不修改登录钥匙串或系统隐私数据库。这个目录被 Git 忽略，私钥权限为 0600。请保留它，重建时不要重新生成身份，也不要将私钥分享出去。

`./scripts/test-signing-identity.sh` 用两个不同版本的应用包验证新版满足旧版的指定身份要求，防止以后重建再次破坏授权。由旧 ad-hoc 版迁移到新签名版，需要为新身份授权一次。

系统授权以正常启动的应用为准；从已获权限的终端启动诊断可能继承终端的权限，不能替代真实授权验证。可用以下命令通过 Launch Services 检查（结果只含权限/帧数/窗口层数，不含桌面画面）：

```sh
open -n dist/MacDuo.app --args --check-perspective --report /tmp/macduo-capture-report.json
```

参考：[Apple 关于指定身份与授权跨版本匹配的说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 性能验证

渲染使用全尺寸取景，合成后进行一次渐变模糊。窗口取景最高 60 fps、背景最高 30 fps，屏幕绘制目标 60 fps。Core Image 编码使用独立串行队列，最多两个在途帧；主线程负责显示同步与状态更新。

```sh
MACDUO_BENCHMARK=1 swift test --filter RendererPerformanceTests
open -n dist/MacDuo.app --args --check-perspective --report /tmp/macduo-capture-report.json
```

离线基准在 3428 × 2178 像素、模糊半径 36 下测量 CPU/GPU 耗时，并检查是否满足 60 Hz 帧预算。真实取景诊断在准备好后运行约 4 秒，最多等待启动 20 秒。`performance` 中的帧率和帧间隔按渲染完成时间统计，不等同于显示器实际呈现时间；不同设备、分辨率和桌面负载会影响结果。

可导出不含桌面内容的渐变模糊测试图：

```sh
MACDUO_RENDER_PREVIEW="$PWD/.build/gradient-blur-preview.png" \
  swift test --filter PlaneRendererTests.testBlurGrowsFromHingeToTopOnBothWindowsAndWallpaper
```
