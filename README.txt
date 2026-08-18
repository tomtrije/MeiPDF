MeiPDF — macOS 原生 PDF 浏览器（专注浏览与打印）

【有 Developer ID 证书 + 公证】
直接把 MeiPDF.app 拖到「应用程序」，双击即可打开，无需任何额外操作。

【没有证书（自用 / 测试）】
macOS 会拦截未签名（仅 ad-hoc）的 app。两种办法：

办法一（推荐）：双击本 DMG 里的「install.command」，它会自动移除隔离属性，
并把 MeiPDF 安装到「应用程序」，然后打开。

办法二（手动）：在终端执行下面这条命令（路径按实际情况改）：
    sudo xattr -rd com.apple.quarantine /Applications/MeiPDF.app
如果是从 DMG 里直接打开，把路径换成 /Volumes/MeiPDF/MeiPDF.app

执行后即可正常打开 MeiPDF。

更多信息见：https://github.com/tomtrije/MeiPDF
