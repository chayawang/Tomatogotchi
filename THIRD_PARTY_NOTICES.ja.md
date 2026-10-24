# ライセンスと出典

[繁體中文](THIRD_PARTY_NOTICES.md) · [English](THIRD_PARTY_NOTICES.en.md) · [日本語](THIRD_PARTY_NOTICES.ja.md)

## 本プロジェクト

Tomatogotchiのコード、および本プロジェクト独自のピクセルキャラクター、墓石、本体、アイコンのソースは、ルートのBSD-3-Clause LICENSEに基づいて提供し、公開アカウントchayawangを著作権者として表記します。標準ライセンスは、公式を装う権利や、許可なく著作権者・貢献者の名前を派生製品の推奨に使う権利を与えません。ライセンスで認められた改変、再配布、商用利用を禁止するものではありません。

## フォント

同梱フォントは`Sources/Tomatogotchi/Resources/OFL.txt`の原文に従います。ダウンロードパッケージには`THIRD_PARTY_LICENSES/OFL.txt`も含みます。Adobe／Sourceフォントの著作権およびReserved Font Nameの告知を含み、SIL Open Font License 1.1に基づきます。プロジェクトのBSDライセンスでフォントのライセンスを置き換えないでください。

## プラットフォームとツール

SwiftUI、AppKit、FoundationなどはAppleのシステムフレームワークで、互換性のあるmacOSとAppleのツールが必要です。現在、Swift Packageに外部パッケージ依存はありません。システムフレームワークやツールを本プロジェクトが再ライセンスすることはなく、GitHub Actionsなどのサービスにはそれぞれの規約が適用されます。

公開素材は本プロジェクトのピクセル格子・ベクター生成ツールで管理し、オリジナルの編集可能なソースは`design/`と`scripts/make-*.py`にあります。第三者が依存関係や素材を追加する際は、対応するライセンス告知も追加してください。
