<p align="center">
  <img src="https://github.com/user-attachments/assets/0b86ad98-ab19-4bf0-a2f7-f6d271cd26bb" width="112" alt="QuotaBar 图标">
</p>

<h1 align="center">QuotaBar</h1>
<p align="center">在 Mac 菜单栏查看 Codex 与 Cursor 的剩余使用量。</p>
<p align="center">原生 Swift · macOS 13+ · 无第三方依赖 · MIT</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/67879f7a-43f1-4f79-b093-5cb0dc6a11f0" width="147" alt="上方显示 Codex 和 Cursor 名称，下方显示剩余百分比">
</p>

QuotaBar 复用你本机 Codex 和 Cursor 的现有登录状态，无需复制令牌或配置 API Key。菜单栏采用两层文字设计，点击即可查看全部额度和重置时间。

<p align="center">
  <img src="https://github.com/user-attachments/assets/4ff098c4-cba0-47ef-a9ed-eae078bb79bc" width="350" alt="QuotaBar 浅色面板">
  <img src="https://github.com/user-attachments/assets/8c0ee0f5-c10f-457b-b79a-8d9a6fc8f92a" width="350" alt="QuotaBar 深色面板">
</p>

*以上为使用演示数据渲染的界面，实际额度由你的账号返回。*

## 功能

- Codex：显示短周期、每周及服务返回的额外额度窗口。
- Cursor：显示总额度、Cursor 模型池、其他模型池和基础美元额度。
- 1 / 5 / 15 分钟自动刷新，手动刷新，电脑唤醒后自动更新。
- 显示各额度的重置时间；读取失败时标注旧数据，避免误判。
- 紧凑面板一次展示全部内容，支持系统浅色与深色外观。
- 可选登录时启动；只驻留菜单栏，不占用 Dock。

## 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 13 Ventura 或更新版本 |
| 处理器 | Apple Silicon 或 Intel；发布包为 Universal 二进制 |
| Codex | 本机已安装 Codex 桌面版，或可定位的 Codex CLI；使用 ChatGPT 订阅账号登录 |
| Cursor | 本机已安装 Cursor，并登录自己的账号 |
| 网络 | 能访问 Codex 和 Cursor 用量服务 |

**Windows / Linux 不支持。** QuotaBar 展示订阅剩余额度；使用 API Key 登录 Codex 时无法获取 ChatGPT 订阅额度。不要求同时安装两个产品，只安装一个时另一项会显示未登录提示。

## 方式一：下载应用直接使用

1. 打开 [Releases](https://github.com/hqx6/QuotaBar/releases/latest)，下载 `QuotaBar-版本号-macOS-universal.zip`。
2. 解压得到 `QuotaBar.app`，将它放到“应用程序”目录，或自己的 `~/Applications` 目录。
3. 先打开 Codex 和 Cursor，分别登录自己的账号。
4. 双击 `QuotaBar.app`。菜单栏出现 `Codex / Cursor`，下方数字就是剩余百分比。
5. 点击菜单栏标签，查看各窗口和模型池的额度、重置时间；右上角可立即刷新。
6. 需要开机自动运行时，勾选面板底部“登录时启动”。如系统要求，在“系统设置 → 通用 → 登录项”中允许 QuotaBar。

发布包使用本地 ad-hoc 签名，未经过 Apple Developer ID 签名及公证。如果 macOS 阻止首次打开，请确认下载来自本仓库的 Releases，再按系统的“隐私与安全性 → 仍要打开”流程处理。无需关闭 Gatekeeper 或系统安全保护。

升级时，先从 QuotaBar 面板点击“退出”，再用新版替换旧的 `.app`，然后重新打开。

## 方式二：在自己的 Mac 上从源码构建

首次使用需要安装 Xcode Command Line Tools：

```sh
xcode-select --install
```

下载并构建：

```sh
git clone https://github.com/hqx6/QuotaBar.git
cd QuotaBar
./scripts/build-app.sh
./scripts/install.sh
```

安装脚本把程序复制到 `~/Applications/QuotaBar.app` 并启动。默认构建当前电脑架构，无需安装 Python、Node.js 或任何 Swift 第三方库。

也可以只构建，然后手动双击 `dist/QuotaBar.app`。

生成同时支持 Intel 和 Apple Silicon 的发布包：

```sh
QUOTABAR_UNIVERSAL=1 ./scripts/package-release.sh
```

输出包含 `.zip` 和对应的 `.sha256` 校验文件。下载后可在同一目录运行 `shasum -a 256 -c 文件名.sha256` 检查完整性。

## 百分比是什么意思？

**所有数字都是剩余比例。** 例如 `72%` 表示当前额度还剩 72%，不是已经用了 72%。

| 显示位置 | 计算口径 |
| --- | --- |
| Codex 菜单栏 | 主 `codex` 额度桶各窗口中最低的剩余比例 |
| Codex 面板 | 每个窗口分别计算 `100 - usedPercent` |
| Cursor 菜单栏 | 优先使用服务返回的总额度剩余比例 |
| Cursor 面板 | 分别显示总额度、Cursor 模型池、其他模型池 |
| Cursor 基础美元额度 | 单独展示；不会用它替代已经返回的总额度比例 |

当 Cursor 没有返回模型池比例时，程序回退到基础套餐额度，并明确标注。不同额度池的比例不能相加。服务提供的是比例，不是剩余请求数或 token 数。

菜单栏只显示整数，面板保留一位小数。Codex 的周额度通常会成为限制最紧的窗口，因此菜单栏可能与短周期额度不同。

## 常见问题

**Codex 显示 `!` 或“未找到 Codex”**

确认 Codex 已安装，并用 ChatGPT 账号登录。默认优先查找 `/Applications/Codex.app/Contents/Resources/codex`，也查找用户应用目录、Homebrew 和 `~/.npm-global/bin`。CLI 位于其他位置时，可指定路径：

```sh
CODEX_BINARY="/你的路径/codex" dist/QuotaBar.app/Contents/MacOS/QuotaBar
```

**Cursor 显示登录已失效**

打开 Cursor 完成登录或更新登录状态，然后点击 QuotaBar 的刷新按钮。程序每次刷新都会重新读取本机登录状态，不会自动替你登录。

**数字后面出现 `!`**

最新读取失败。显示的数字是本次启动以来最后一次成功读取的值；面板会标注“数据已过期”及错误原因。检查网络、登录状态，再刷新。

**为什么 Cursor 的美元余额和总额度比例对不上？**

Cursor 返回的基础美元额度与模型池总额度可能采用不同的额度基数。程序分别展示，遵循客户端返回的百分比，不把两种口径混合计算。

**面板重置时间和网页不同？**

面板按这台 Mac 的系统时区显示服务返回的重置时间。查看系统时区是否正确。比例与时间均取自服务，不在本机预测额度重置。

**找不到菜单栏标签**

菜单栏空间不足时，关闭部分菜单栏工具或在菜单栏管理工具中检查是否被隐藏。程序没有 Dock 图标。

## 隐私与实现

- Codex：调用本机官方 `codex app-server` 的 `account/rateLimits/read`，由官方程序处理现有登录状态。
- Cursor：SQLite **只读**打开 `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`，将现有登录令牌仅用于 `https://api2.cursor.sh` 的用量与套餐查询。
- Cursor 网络会话不持久化 Cookie，禁用 HTTP 重定向；令牌只保留在内存中，不打印、不复制、不保存。
- 不访问代码、聊天记录或浏览器 Cookie，不把凭证发送给第三方，不写磁盘用量缓存。
- 不发起模型推理请求，也不消耗推理额度。

Cursor 的个人用量查询使用客户端内部接口，并非稳定的公共 API，服务更新后可能需要适配。本项目是独立工具，与 OpenAI、Anysphere 无隶属关系。

## 开发与验证

```sh
# 解析测试：缺失字段、多额度桶、超额、两种 Cursor 额度口径
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --disable-sandbox

# 使用自己的登录状态检查真实数据；只输出用量，不输出凭证
dist/QuotaBar.app/Contents/MacOS/QuotaBar --check

# 用演示数据生成浅色/深色面板和菜单栏标签，不读取账号
dist/QuotaBar.app/Contents/MacOS/QuotaBar --render-preview docs/images --demo
```

| 文件 | 用途 |
| --- | --- |
| `Sources/QuotaBar/App.swift` | 菜单栏、紧凑面板、自动刷新与开机启动 |
| `Sources/QuotaBar/Providers.swift` | Codex / Cursor 用量读取 |
| `Sources/QuotaBar/Usage.swift` | 数据解析与额度口径 |
| `scripts/make-icon.swift` | 原创图标及各尺寸图标生成 |
| `scripts/build-app.sh` | 构建、生成 `.icns`、打包并签名 |
| `scripts/package-release.sh` | 生成下载包与 SHA-256 校验文件 |

参考：[Codex App Server](https://learn.chatgpt.com/docs/app-server)、[Cursor 用量与限制](https://prod.cursor.com/help/models-and-usage/usage-limits)。

## License

[MIT](LICENSE)。源码与原创图标均随本仓库提供。
