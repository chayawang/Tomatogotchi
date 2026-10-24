# Tomatogotchi

住在 Mac 桌面角落的像素電子雞：透過工作計時、照顧與休息，一起養成陪伴習慣。不必登入、不需要 AI API。

## 官方來源與安全

- 官方原始碼：[chayawang/Tomatogotchi](https://github.com/chayawang/Tomatogotchi)
- **唯一官方 App 下載管道：[GitHub Releases](https://github.com/chayawang/Tomatogotchi/releases)**
- 請核對發布帳號、檔名、版本與官方 SHA-256；相同圖示或名稱不代表相同來源。
- Fork／第三方修改不受官方背書。原始碼與原創素材採 [BSD-3-Clause](LICENSE)，允許修改、再散布及商用，但必須保留授權與免責聲明，不得未經許可以著作權人或貢獻者的名字為衍生產品背書。

[官方來源與免責](DISCLAIMER.zh-TW.md) · [安全通報](SECURITY.md) · [第三方授權](THIRD_PARTY_NOTICES.md)

## 目前版本

**1.0.2 build31，公開測試版**。下載包僅 Apple Silicon（arm64），最低宣告 macOS 13，但目前實機測試基準是 Apple Silicon／macOS 14.4.1；Intel及最低系統尚未實測。使用 ad-hoc 開發簽章，**未 Developer ID 簽章、未 Apple 公證**；下載後的 Finder／Gatekeeper 安裝及部分原生操作仍待人工補驗，不把自動渲染或程序檢查當作完整實機驗證。

- 每輪工作與休息時間可自行設定，提供快捷建議值。
- 工作時待機、睡覺、玩及小範圍走動；真正散步時可在目前螢幕桌面移動，到期返回。
- 未知蛋可孵化貓、恐龍、狗、達摩或哥布林，既有寵物不換種。
- 死亡寵物以墓碑紀錄名稱、見面及死亡時間，告別後保留。

## 使用

請讀[使用與安裝說明](docs/user-guide.md)及[版本限制](docs/releases/v1.0.2.md)。下載檔可用 `shasum -a 256 "實際下載檔案路徑"` 核對官方 Release 的 SHA256SUMS.txt。對照值必須來自本倉庫，不以第三方附帶校驗值證明來源。

## 從原始碼建置

需要 macOS、Apple Command Line Tools（`xcode-select --install`）及 Swift 5.9 或相容工具鏈。

```sh
bash scripts/build-app.sh
```

產物在 `build/Tomatogotchi.app`。完整自動驗證：

```sh
bash scripts/verify.sh
```

驗證使用臨時獨立資料；不要把測試資料當正式存檔。若需手動測試，執行 `python3 scripts/prepare-native-qa.py` 可建立固定獨立資料目錄的 QA App，再依輸出路徑開啟；不要直接以正式資料測試。驗證不會替你改系統安全權限。

來源不含任何既有使用者或 QA 寵物資料。像素素材的可編輯來源在 `design/`，產生工具在 `scripts/make-*.py`；字型另依 OFL 授權。
