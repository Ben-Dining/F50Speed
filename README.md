# F50Speed

一个 macOS 菜单栏实时网速工具，直连中兴 F50 5G 热点（192.168.0.1）的免登录接口读取上下行速率；F50 不在身边时，自动回退到读取 Mac 自身网卡速率。单文件 Swift 源码，零依赖，本地编译即用。

A macOS menu-bar speed monitor that reads real-time up/down throughput directly from the ZTE F50 5G hotspot (192.168.0.1) via its login-free API. When the F50 is unreachable, it automatically falls back to measuring the Mac's own network interface. Single-file Swift source, zero dependencies, build and run.

![菜单栏 / Menu bar](assets/screenshot-menubar.png)

## 功能 / Features

- **菜单栏实时速率** / Real-time speeds in the menu bar：▼下行 ▲上行，上下两行或左右并排可切 ▼down ▲up, stacked or side-by-side layout
- **悬浮窗** / Floating window：大号数字 + 最近速率曲线，可拖到任意位置 big numbers + recent throughput sparkline, draggable anywhere
- **两种速率来源** / Two speed sources：
  - F50 免登录接口（`flux_realtime_tx_thrpt / rx_thrpt`），显示 5G 信号、在线设备数 F50 login-free API, plus 5G signal and client count
  - F50 不可达时自动改用本机默认网卡计数差值，连其他 Wi-Fi 也能用 falls back to the Mac's primary interface counters when the F50 is away
- **1 秒级刷新** / Second-level refresh：默认 1 秒，可切 2 / 5 秒 1s default, 2s / 5s optional
- **Mbps / MB/s 单位切换** / Mbps / MB/s unit toggle
- **中英双语界面** / Bilingual UI：中文 / English 一键切换 one-click switch
- **开机自动启动** / Launch at login
- 无 Dock 图标、无外部依赖、无网络权限弹窗 no Dock icon, no dependencies, no network permission prompts

![悬浮窗 / Floating window](assets/screenshot-float.png)

## 系统要求 / Requirements

- macOS 13 Ventura 或更高 or later
- 与 F50 在同一网络（或任何网络——会自动切换到本机速率） on the same network as the F50 (or any network — it falls back automatically)

## 构建 / Build

```bash
git clone https://github.com/<your-name>/F50Speed.git
cd F50Speed
./build.sh
```

`build.sh` 用 `swiftc` 编译 `Sources/main.swift` 并打包成 `F50Speed.app`。

`build.sh` compiles `Sources/main.swift` with `swiftc` and assembles `F50Speed.app`.

也可以手动编译 / Or compile manually:

```bash
swiftc -O -swift-version 5 Sources/main.swift -o F50Speed
```

## 安装 / Install

把 `F50Speed.app` 拖进「应用程序」文件夹，双击运行；在菜单栏图标菜单里勾选「开机自动启动 / Launch at login」。

Drag `F50Speed.app` to Applications and launch it. Enable "Launch at login" from the menu-bar menu.

## 使用 / Usage

点击菜单栏图标打开菜单：

Click the menu-bar icon:

| 菜单 / Menu | 说明 / Description |
|---|---|
| 状态行 / Status line | 网络类型 · 信号 · 在线设备 / network type, signal, clients |
| 刷新间隔 / Refresh interval | 1 秒（默认）/ 2 秒 / 5 秒 1s (default) / 2s / 5s |
| 速率单位 / Speed unit | Mbps（网络速率）/ MB/s（下载速度）Mbps (line rate) / MB/s (byte rate) |
| 菜单栏布局 / Menu bar layout | 上下显示 / 左右显示 stacked / side by side |
| 显示悬浮窗 / Show floating window | 开关速率悬浮窗 toggle the floating window |
| 开机自动启动 / Launch at login | 注册/取消登录项 register/unregister login item |
| 语言 / Language | 中文 / English |
| 打开 F50 管理页 / Open F50 admin | 浏览器打开 192.168.0.1 open 192.168.0.1 |

所有偏好即时生效并本地保存。All preferences apply instantly and persist locally.

## 原理 / How it works

F50 的 Web 后台在未登录状态下通过以下接口暴露实时速率：

The F50 exposes real-time throughput without login at:

```
http://192.168.0.1/goform/goform_get_cmd_process?cmd=flux_realtime_tx_thrpt,flux_realtime_rx_thrpt,network_type,network_signalbar,wifi_access_sta_num&multi_data=1
```

返回 JSON，速率单位为 bps。回退模式用 `getifaddrs` 读取默认路由接口的字节计数，按采样间隔求差值换算 bps，Wi-Fi 名称通过 `networksetup -getairportnetwork` 获取。

It returns JSON with speeds in bps. Fallback mode samples the default-route interface byte counters via `getifaddrs` and differentiates over the sampling interval; the Wi-Fi SSID comes from `networksetup -getairportnetwork`.

> 注意：本工具仅适用于你自己的 F50 所在的局域网，接口行为随固件版本可能不同。
> Note: this tool is intended for your own F50's local network; the API behavior may vary by firmware version.

## 命令行参数 / Command-line arguments

- `--float`：启动时直接打开悬浮窗 open the floating window at launch
- `--probe`：取一次 F50 数据并打印，然后退出 fetch once from the F50, print, exit
- `--probe-local`：采样本机网卡 2 秒计算速率并打印，然后退出 sample the local interface for 2s, print computed rates, exit

## 许可证 / License

[MIT](LICENSE)
