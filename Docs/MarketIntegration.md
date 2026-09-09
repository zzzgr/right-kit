# 市场与导入指南

RightKit 1.2.1 支持动作市场接入。市场负责动作编辑、版本发布与升级日志；客户端负责检查内容、配置本机环境和执行保存后的动作。网页与客户端无需共享数据库或管理员登录。

## 从市场使用动作

1. 在网页动作详情中选择版本，点击「在 RightKit 中打开」。客户端会下载并校验这个固定版本，展示动作说明、源代码、运行依赖和历史版本。
2. 点击「导入为草稿」，填写本机解释器、工作目录和需要的环境变量。依赖由用户在本机准备，客户端不会自动安装。
3. 使用测试文件检查实际效果，再保存动作。保存前不会改变 Finder 菜单；导入流程本身不会执行脚本或读取钥匙串。

客户端的动作说明和升级日志支持 Markdown 标题、粗体、列表、引用、代码块、任务列表、链接和参数表格。宽表格与长代码可横向滚动；源码页仍按原文显示。图片保留替代文字，预览说明时不会自动加载外部图片。

网页的「添加到 RightKit」可以配置当前市场，也可以在客户端自定义动作窗口顶部切换到「动作市场」，打开右上角的「市场设置」，填写一个市场首页或目录地址。市场列表占据完整内容区，点击动作后在弹窗中查看详情。HTTP 和 HTTPS 均可使用，例如 `http://192.168.1.2:3000`。尚未配置市场时，首次导入经过验证的市场动作会保存对应市场地址。

市场设置只有一个地址输入框，支持修改和清除配置。保存前会验证新地址；验证失败时保留原有地址和缓存。编辑地址不会改写已安装动作的更新来源，导入其他来源的动作也不会自动更换当前市场。

动作市场与「我的动作」默认每页 20 条，可切换为 50 / 100 条。市场搜索和语言筛选覆盖整个市场，再返回当前页；切换条件时回到第一页。「仅看可更新」按已安装动作的 ID 查询，避免漏掉其他页面的更新。页面缓存按查询地址分别保存，离线时只展示对应查询的缓存。旧静态市场没有分页元信息时使用完整读取兼容。

旧版保存了多个市场时，升级后保留第一个有效市场，原始配置备份到 `~/Library/Application Support/RightKit/Markets/sources.legacy.json`，已安装的动作不受影响。

网页唤起后会立即显示加载界面。下载或校验失败时，预览窗口会显示具体原因；临时网络故障可以点击「重新读取」。取消下载后不会继续弹出预览，连续打开链接时显示最后一次选择的动作。

## 更新与本地修改

在已安装动作中点击「检查市场更新」，或在「动作市场」刷新来源，再选择「仅看可更新」。查看新版本的源码和升级日志后，将更新导入为草稿。

- 更新按“规范化市场地址 + 动作 ID”匹配，来自不同市场的相同 ID 不会互相覆盖。
- 客户端以最后导入的动作包为基线进行三方合并，保留未冲突的本地修改，包括新增或删除的环境变量；发生冲突时可以选择保留本地改动。
- 更新保留本地动作 UUID、启用状态、解释器和工作目录路径。同名且密钥类型未改变的环境变量沿用本地引用，导入时不读取密钥值。
- 重新打开同版本会定位已安装动作；「导入独立副本」创建另一条动作，并停止跟随原动作更新。
- 网页可选择旧版本后导入，客户端会提示当前已安装的较新版本。回退仍需导入草稿并保存。
- 市场刷新失败时保留上次成功缓存，删除订阅不会删除已安装的动作。

## 将本地动作发布到市场

在本地动作中点击「复制动作包」，粘贴到市场后台的 JSON 编辑器。导出保留可移植的脚本、适用条件、依赖和说明，移除密钥值与本机专用路径。

市场新建动作时由服务器生成公开 UUID；填写 SVG 图标后保存即可。发布需提供递增的版本号和升级日志，同一动作的所有版本合并为一张市场卡片。已发布 JSON、图标和摘要不可覆盖，草稿编辑不影响公开版本。

## 两端接口

| 接口 | 用途 |
| --- | --- |
| `/.well-known/rightkit-market.json` | 市场发现 |
| `/rightkit/market.json` | 分页目录与 ETag |
| `/rightkit/actions/{id}/{version}.json` | 不可变的 `rightkit.action` v1 动作包 |
| `/rightkit/actions/{id}/{version}.png` | 固定版本的 PNG 图标 |
| `/rightkit/actions/{id}/versions.json` | 分页版本记录、升级日志与摘要 |

市场保留 SVG 源码并生成 64×64 PNG。动作包继续使用现有 v1 图标格式，Finder 无需渲染 SVG。

分页查询使用 `page`、`pageSize`、`q`、`language`，默认 20 条，单页最多 100 条；更新查询额外传入 `ids`。目录返回可选的 `pagination: { page, pageSize, total, totalPages }`，并保留兼容的 `next` 链接。服务端对已发布内容完成搜索和筛选后分页，不会把草稿发给客户端。后台和网页使用相同的查询规则。

网页入口使用以下 URL，参数必须进行 URL 编码：

```text
rightkit://market?url=<市场首页或目录地址>
rightkit://import?url=<固定版本动作包地址>&market=<市场地址>&sha256=<SHA-256>
```

旧版仅含 `url` 的导入链接仍可使用。客户端核对目录或历史记录中的动作 ID、版本与摘要后，才将链接归属到市场更新来源；未能核对时作为独立链接导入。网络请求限制响应大小与分页数量，并校验同源地址、重定向和原始字节摘要。

Web 实现和完整协议说明位于同级项目的 [right-kit-market/docs/rightkit-integration.md](../../right-kit-market/docs/rightkit-integration.md)。

## 本地联调

先在 `right-kit-market` 中启动服务，并确保至少有一个已发布动作：

```sh
npm install
npm run admin:setup
MARKET_BASE_URL=http://127.0.0.1:3000 npm run dev -- --hostname 127.0.0.1
```

在 `right-kit` 中执行：

```sh
./Scripts/generate-project.sh
MARKET_INTEGRATION_URL=http://127.0.0.1:3000 swift test --package-path Packages/RightKitShared
```

测试读取真实市场，检查目录、动作包、PNG 和升级日志，不写入服务器。不设置 `MARKET_INTEGRATION_URL` 时，常规测试仍用临时 HTTP 服务验证分页、缓存、摘要、重定向与响应限制。

市场设置的持久化、链接编辑、并发刷新和 Markdown 排版结构使用独立的 XCTest target 验证，测试数据全部位于临时目录，无需启动 App 或 Finder：

```sh
xcodebuild -project RightKit.xcodeproj -scheme RightKit -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test \
  CODE_SIGNING_ALLOWED=NO ENTITLEMENTS_REQUIRED=NO
```

需要人工验证网页唤起和 Finder 时，使用已有本地安装流程安装客户端：

```sh
./Scripts/install-local.sh
```

从 `/Applications` 运行，按安装脚本的提示确认 Finder 扩展已启用，再在「市场设置」中添加 `http://127.0.0.1:3000`。不要直接运行 DerivedData 中的 App。

Debug 和 Release 均支持 HTTP 和 HTTPS，不限于本机地址。网页默认监听所有 IPv4 网卡；本机可配置 `http://127.0.0.1:3000`，同一局域网中的其他 Mac 可配置这台服务器的局域网地址。

网站目录、图标、版本记录和网页跳转链接随当前访问地址生成，无需为本机和局域网分别修改服务器配置。`MARKET_BASE_URL` 是发布脚本等无请求上下文时使用的默认地址，可设置为 HTTP 或 HTTPS。经过反向代理时保留 `Host`，并传递实际的 `X-Forwarded-Proto`。
