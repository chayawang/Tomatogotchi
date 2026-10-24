# Tomatogotchi

[繁體中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

Macのデスクトップの片隅で暮らすピクセルのペット。作業タイマー、お世話、休憩を通じて、一緒に毎日の習慣を育てます。ログインやAI APIは不要です。

## 公式ソースと安全性

- 公式ソース：[chayawang/Tomatogotchi](https://github.com/chayawang/Tomatogotchi)
- **公式Appの唯一のダウンロード先：[GitHub Releases](https://github.com/chayawang/Tomatogotchi/releases)**
- 公開者、ファイル名、バージョン、公式のSHA-256を確認してください。名前やアイコンが同じでも、配布元が同じとは限りません。
- Forkや第三者による改変版を公式が推奨・保証するものではありません。ソースコードとオリジナル素材は[BSD-3-Clause](LICENSE)に基づき、条件を守れば改変、再配布、商用利用が可能です。ライセンスと免責条項を保持し、許可なく著作権者や貢献者の名前を派生製品の推奨に使用しないでください。

[公式配布元と免責事項](DISCLAIMER.ja.md) · [セキュリティポリシー](SECURITY.ja.md) · [第三者ライセンス](THIRD_PARTY_NOTICES.ja.md)

## 現在のバージョン

**1.0.2 build31、公開テスト版**。配布パッケージはApple Silicon（arm64）専用です。宣言上の最低要件はmacOS 13ですが、実機テストの基準はApple Silicon／macOS 14.4.1です。Intelと最低OSでの実機検証は未実施です。ad-hoc開発署名を使用しており、**Developer ID署名およびAppleの公証はありません**。ダウンロード後のFinder／Gatekeeperによるインストールや一部のネイティブ操作は手動検証が必要です。自動描画・プロセス検査は、実機での全操作の検証を意味しません。

- 各ラウンドの作業・休憩時間を自由に設定でき、候補のショートカットもあります。
- 作業中は待機、睡眠、遊び、短い移動を行います。実際の散歩では現在の画面のデスクトップを歩き、時間が来ると元の位置に戻ります。
- 未知の卵から猫、恐竜、犬、だるま、ゴブリンのいずれかが生まれます。既存のペットの種類は変わりません。
- 亡くなったペットの名前、出会った日時、死亡日時を墓石に記録し、お別れ後も保存します。

## 使い方

[インストールと使い方](docs/user-guide.ja.md)、[バージョンの制限事項](docs/releases/v1.0.2.ja.md)をお読みください。`shasum -a 256 "ダウンロードしたファイルのパス"`で、公式ReleaseのSHA256SUMS.txtと照合できます。比較する値は本リポジトリから取得してください。第三者が添付した値だけでは公式配布元の確認にはなりません。

## ソースからビルド

macOS、Apple Command Line Tools（`xcode-select --install`）、Swift 5.9または互換ツールチェーンが必要です。

```sh
bash scripts/build-app.sh
```

### ビルド中のXCTest／PlatformPath警告

Command Line Toolsのみを使用する一部の環境では、`could not determine XCTest paths`や`unable to lookup item 'PlatformPath'`が表示されることがあります。[SwiftPMの報告](https://github.com/swiftlang/swift-package-manager/issues/7480)では、使用するツールによって警告だけの場合とビルドが中断する場合が記録されています。

今回のコマンドが正常終了（終了コード0）し、最後に`Built: .../build/Tomatogotchi.app`が表示されることを確認してください。`Generated editable pixel egg...`はアイコン生成の完了だけを示します。警告だけ、または以前のビルドで残ったAppの存在だけでは、今回の成功は判断できません。

中断した場合は、現在のmacOSに対応するCommand Line Toolsを更新して再試行してください。選択中のツールは`xcode-select -p`と`swift --version`で確認できます。完全版Xcodeをインストール済みなら、[Appleのツール選択手順](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings)に従い、**Xcode → Settings → Locations → Command Line Tools**でインストール済みのXcodeを選び、再ビルドする方法もあります。これは切り分けの選択肢であり、すべてのエラーの解決を保証しません。改善しない場合は、個人のパスなどの私的情報を除いたうえで、macOS／Swiftのバージョンとエラー全体を報告してください。

[公式Releases](https://github.com/chayawang/Tomatogotchi/releases)からAppをダウンロードして利用するだけなら、XcodeやCommand Line Toolsは不要です。

生成先は`build/Tomatogotchi.app`です。自動検証一式：

```sh
bash scripts/verify.sh
```

テストは一時的な独立データを使います。手動テストでは`python3 scripts/prepare-native-qa.py`で独立データ用のQA Appを作成し、表示されたパスから開いてください。実際のペットデータでテストしないでください。検証はシステムのセキュリティ権限を変更しません。

既存ユーザーやQA用ペットのセーブデータは含みません。編集可能なピクセル素材は`design/`、生成ツールは`scripts/make-*.py`にあります。フォントは別途OFLライセンスに従います。
