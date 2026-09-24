# F-Stopwatch

跨端（Windows + Android）计时/停表应用。用 **Flutter（Dart 单代码库）** 开发，计时代码双端共享。

- **Windows 端**：主窗口显示总时间与打点列表；支持**自定义全局热键**（应用不在前台也可用）分别触发“暂停/开始”与“计次+1”，并显示每次（本次 vs 累计）时间。
- **Android 端**：无需自定义按键；**悬浮窗**显示总时间，下方有“暂停/开始”和“计次+1”两个按钮，可悬浮在其他应用之上使用。
- **Web 端**：功能与主端一致（计时、暂停/开始、计次+1、重置、打点列表），**不绑定热键**，用于快速调试。

## 目录结构

```
lib/
  main.dart                  # 按平台分发入口
  stopwatch_model.dart       # 共享计时/停表核心模型
  format.dart                # 时间格式化
  hotkeys.dart               # Windows 全局热键 + 可配置热键设置
  overlay_bridge.dart        # Android 悬浮窗双向通道封装
  src/windows/windows_app.dart
  src/android/android_app.dart
  src/web/web_app.dart        # Web 调试端（无热键）
android/app/src/main/...     # MainActivity(渠道)、OverlayService(悬浮窗)、Manifest
web/                         # Web 脚手架（index.html、manifest.json、图标）
```

## 一、前置条件（构建端，需自行安装）

| 平台 | 依赖 |
| --- | --- |
| 通用 | [Flutter SDK](https://flutter.dev)（≥3.16，自带 Dart） |
| Windows | Visual Studio 2022 + “使用 C++ 的桌面开发”工作负载 |
| Android | Android Studio / Android SDK + Platform 33+、JDK 11+（如 OpenJDK 17） |
| Web | 无需额外依赖（Chrome / Edge 调试） |

## 二、生成平台脚手架 + 拉取依赖

由于本仓库只含跨端公共代码与安卓自定义平台源码，`windows/` 与剩余的 `android/`（gradle、res 等）标准脚手架需用你的 Flutter 版本生成。在项目根目录执行：

```bash
flutter create --platforms=windows,android --project-name f_stopwatch --org com.f.s .
flutter pub get
```

`web/` 脚手架已随仓库提供，若缺失可执行 `flutter create --platforms=web .` 补全。

> 说明:`flutter create` 只会补全缺失文件,`lib/`、`android/.../*.kt`、`AndroidManifest.xml` 等已有文件会被保留。当前应用 ID(`applicationId`/`namespace`)为 **`com.f.s.f_stopwatch`**,见 `android/app/build.gradle.kts`;启动类为 `.MainActivity`,悬浮窗服务为 `.OverlayService`。如需改包名,请同时改 `build.gradle.kts` 的 `namespace`/`applicationId` 并把 `android/app/src/main/kotlin/com/f/s/f_stopwatch/` 三个 `.kt` 的 `package` 声明一致,再改 `AndroidManifest.xml` 的 `android:label`。建议保持 `compileSdk`/`targetSdk` ≥ 34(悬浮窗 `specialUse` 前台服务需要)。
```

## 三、运行

```bash
# Windows
flutter run -d windows

# Android（需连接的设备或模拟器）
flutter run -d <device-id>

# Web（调试，浏览器打开）
flutter run -d chrome
```

构建/调试检查：`flutter analyze`、`flutter test`。

## 四、使用

### Windows
- 界面按钮：开始/暂停、计次+1、重置。
- “热键设置”面板可修改两个动作的**按键与修饰键**（默认：F2=暂停/开始，F3=计次+1），选择后自动保存并重新注册。
- 全局热键：应用不在前台时按热键同样生效。

### Android
1. 首次进入，点击“去授权”，在跳转的系统设置中允许“悬浮窗”权限。
2. 返回应用，点击“启动悬浮窗”。
3. 悬浮窗显示总时间与两个按钮；点击“暂停/开始”或“计次+1”，主界面打点与时间同步更新。
4. “停止悬浮窗”可关闭；悬浮窗播放时右下会有一条常驻通知。

> 注意：悬浮窗依赖应用进程存活；在最近任务中“上滑”划掉应用会停止计时。常规切后台（Home/多任务）不影响运行。

## 五、说明
- 计时逻辑全部在 Dart 侧（`StopwatchModel`），通过 `MethodChannel`/`EventChannel` 与原生悬浮窗通信。
- Windows 全局热键由 `hotkey_manager` 插件提供系统级热键注册，无需手写 C++。

## 六、Android 打包与调试

> 以下 3 个环境变量按你本机实际情况设置(本文以 `D:\AndriodSDK` + `D:\JDK\jdk21` 为例,命令行一次会话内生效):

```powershell
$env:ANDROID_HOME='D:\AndriodSDK'
$env:ANDROID_SDK_ROOT='D:\AndriodSDK'
$env:JAVA_HOME='D:\JDK\jdk21'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
```

**1) 列出连接中的设备/模拟器**

```powershell
E:\mrfz\adb.exe devices
# 例如输出 emulator-7554  device 即连接成功
```

**2) 调试运行(app 启动即附加,改代码热重载)**

```powershell
flutter run -d 7554        # 7554 换成上一步的设备 id;也可用 flutter devices 获取
```
- 正在运行中输入 `r` 热重载、`R` 热重启、`q` 退出。
- 看原生(Kotlin)日志:另开终端执行 `E:\mrfz\adb.exe logcat` 或 `adb logcat -s AndroidRuntime E flutter`。

**3) 打调试/发布 APK**

```powershell
flutter build apk --debug     # 生成 build\app\outputs\flutter-apk\app-debug.apk
flutter build apk --release   # 生成 build\app\outputs\flutter-apk\app-release.apk
```

**关于体积（debug 包为什么很大）**

`--debug` 只为开发调试服务,内嵌整套 JIT 产物(约 43MB 的 `kernel_blob.bin`)、调试 VM 快照、Vulkan 校验层,并且默认一次打进 **arm64/armeabi-v7a/x86_64 三种 CPU 架构**,所以 debug APK 通常 100MB+。发布/装机请走 **release**,同功能单架构实测约 **16MB**。

**想拿到最小的 release 包:**

```powershell
# 最常用:只打 arm64(日常真机),单包约 15-16MB
flutter build apk --release --target-platform android-arm64

# 按 CPU 架构拆分(发到应用市场时用),每个 ABI 一个小包
flutter build apk --release --split-per-abi

# 兼容三架+旧设备,单一 fat APK(较大,约 30MB)
flutter build apk --release

# Google Play 渠道用 aab(体积最优,商店按设备下发 ABI)
flutter build appbundle
```
> release 包默认走 **debug 签名**(见 `build.gradle.kts`),仅方便测试;正式上架前需自行配置 release keystore。

**4) 把 APK 装到设备并启动(用的是我们改过的包名 `com.f.s.f_stopwatch`)**

```powershell
E:\mrfz\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
E:\mrfz\adb.exe shell "am start -n com.f.s.f_stopwatch/.MainActivity"
```

**5) 悬浮窗相关的已知注意点**
- 首次进入需在系统设置里给本应用开启「悬浮窗/显示在其他应用上层」权限。
- 悬浮窗按钮、颜色/大小/透明度配置在 APP 首页右上角 📌「浮窗设置」里。
- 把 app 从最近任务上滑划掉会杀掉进程、悬浮窗与计时一并停止;普通切后台不影响。
- 改图标:先准备好 PNG(本项目用 `tool_logo_1024.png`,由 `f_stopwatch_logo.svg` 栅格化而来),再改 `pubspec.yaml` 里 `flutter_launcher_icons` 的 `image_path`,执行 `dart run flutter_launcher_icons`。

## 七、Web 打包与调试

Web 端与 Android/Windows 共用同一套 Dart 计时代码，**不绑定热键**，主要用于快速调试 UI/逻辑。

**1) 浏览器调试(热重载)**

```powershell
flutter run -d chrome      # 打开 Chrome
# 或起一个只提供静态页面的本地服务(不自动开浏览器):
flutter run -d web-server --web-port 8080
# 然后手动访问 http://localhost:8080
```

**2) 打发布产物(纯静态文件)**

```powershell
flutter build web
# 产物在 build\web,\部署到任意静态服务器/CDN 即可
```

**3) 本地起 HTTP 服务预览发布产物**(任选其一):

```bash
# 法一:python 自带
python -m http.server 8000 --directory build/web   # 访问 http://localhost:8000

# 法二:node 的 npx serve
npx serve build/web
```

**4) 说明**
- 首次访问需要几秒加载 `flutter_bootstrap.js` 与 CanvasKit,属正常现象。
- Web 端悬浮窗/原生通道相关功能不可用(那是 Android 原生的),Web 只提供主界面计时交互。