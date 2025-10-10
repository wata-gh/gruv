# [org]/[repo] 開発状況まとめ（[start date]〜[end date], UTC）

> **使い方メモ**
> - 期間に応じて自然な表現（例: 「約1週間」「約2週間」「約1ヶ月」など）を使ってください。開始日と終了日から日数を計算し、もっとも近い期間表現を採用します。
> - 直近で動きのあった Pull Request / Issue / Discussion は、可能な限り個別URLを添えて列挙します（GitHub の issue/PR/Discussion の絶対リンクを貼る）。
> - 各セクションの要約は、期間内のハイライトやトレンドを中心に簡潔にまとめてください。
> - サンプル値はすべて差し替えて利用してください。

## 集計対象
- 期間: [start date]〜[end date]（UTC, [duration label]）
- リポジトリ: https://github.com/[org]/[repo]

## 全体サマリー
- PR活動: [Pull Request activity summary。例: "XX件が更新（過去約1週間, 検索APIベース）"]
- Issue活動: [Issue activity summary]
- Discussion活動: [Discussion activity summary]
- リリース: [Release summary]

## Pull Request（主な動き）
- 直近更新PR例
  - [#[number] [state]: [title]](https://github.com/[org]/[repo]/pull/[number])
  - [...必要数だけ列挙]
- 傾向
  - [期間内のPRの傾向や特徴を箇条書きで記載]
- 参考: https://github.com/[org]/[repo]/pulls?q=is%3Apr+updated%3A%3E%3D[start date]

## Issues（主なトピック）
- 直近更新Issue例
  - [#[number]: [title]](https://github.com/[org]/[repo]/issues/[number])
  - [...必要数だけ列挙]
- 傾向
  - [期間内のIssueの傾向や特徴を箇条書きで記載]
- 参考: https://github.com/[org]/[repo]/issues?q=is%3Aissue+updated%3A%3E%3D[start date]

## Discussions
- 直近更新
  - [#[number]: [title]（更新日: YYYY-MM-DD）](https://github.com/[org]/[repo]/discussions/[number])
  - [...必要数だけ列挙]
- 傾向: [Discussionの傾向を1〜2文で記載]
- 参考: https://github.com/[org]/[repo]/discussions

## リリース状況（リリーススケジュール）
- 安定版リリース（日時はUTC）
  - [version]（[release date]） — [主な内容や補足]
  - [...必要数だけ列挙]
- α/β/プレリリース（必要に応じて）
  - [version]（[release date]） — [主な内容や補足]
  - [...必要数だけ列挙]
- 特徴
  - [期間内のリリース運用の特徴を箇条書きで記載]
- 参考: https://github.com/[org]/[repo]/releases

## まとめ（この期間のトレンド）
- [期間の特徴・トレンド①]
- [期間の特徴・トレンド②]
- [期間の特徴・トレンド③]

## 参考リンク
- PR検索: https://github.com/[org]/[repo]/pulls?q=is%3Apr+updated%3A%3E%3D[start date]
- Issue検索: https://github.com/[org]/[repo]/issues?q=is%3Aissue+updated%3A%3E%3D[start date]
- Discussions: https://github.com/[org]/[repo]/discussions
- Releases: https://github.com/[org]/[repo]/releases
