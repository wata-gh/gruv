# [org]/[repo] 最近1ヶ月の開発状況まとめ（[start date]〜[end date], UTC）

## 集計対象
- 期間: 2025-08-15〜2025-09-15（UTC, 約1ヶ月）
- リポジトリ: https://github.com/[org]/[repo]

## 全体サマリー
- PR活動: 670件が更新（過去30日, 検索APIベース）
- Issue活動: 777件が更新（過去30日, 検索APIベース）
- Discussion活動: 2件が更新
- リリース: 20件（安定版4件＋α版多数）。最新系は 0.35.0-alpha の連続リリース

## Pull Request（主な動き）
- 直近更新PR例
  - #3608 open: fix(tui): update full-auto to default preset
  - #3607 open: Don’t show the model for apikey
  - #3581 open: Fix get_auth_status response when using custom provider
  - #3603 open: fix: model family and apply_patch consistency
  - #3596 closed: fix(core): flaky test completed_commands_do_not_persist_sessions
  - #3587 closed: add(core): display command without cd prefix
- 傾向
  - TUI/UXの微修正、認証・プロバイダ周辺の安定化、テストのフレーク修正、apply_patchの整合性改善などの品質向上PRが継続
  - オープンとクローズが活発に回っており、短サイクルで細かい改善を積み上げる運用
- 参考: https://github.com/openai/codex/pulls?q=is%3Apr+updated%3A%3E%3D2025-08-15

## Issues（主なトピック）
- 直近更新Issue例
  - #3609: Github Copilot Provider（プロバイダ連携要望）
  - #1797: [Feature Request] PDF support（PDF対応要望）
  - #1243: 「Sign in With ChatGPT」機能の堅牢化（様々なアカウント形態への対応）
  - #3561: 変更内容に関する誤った説明（hallucination/説明整合性の課題）
  - #3600: --resume / --continue のプロジェクト単位動作
  - #3599: Planの更新が初回のみで継続更新されない
  - #3277: CLIの初期メッセージ/ショートカット不具合でスタック
  - #3572: セッションログが platform.openai.com/logs に現れない
  - #3454: network_access パーミッションが機能していない
  - #2628: プロジェクト単位のMCP
- 傾向
  - 機能要望（PDF対応、外部プロバイダ統合、プロジェクト単位設定/MCPなど）
  - 安定性/信頼性（プラン更新、初回体験、ログ連携、パーミッション、説明の正確性）
  - コア動作の一貫性やUXの改善要望が継続
- 参考: https://github.com/openai/codex/issues?q=is%3Aissue+updated%3A%3E%3D2025-08-15

## Discussions
- 直近更新（過去30日で2件）
  - #1076: Resuming a previous session（2025-09-10更新）
  - #1327: Feature Request: Support for Additional VCS (e.g., Jujutsu)（2025-09-02更新）
- 傾向: 機能要望や使い方・ワークフローに関する議論が中心
- 参考: https://github.com/openai/codex/discussions

## リリース状況（リリーススケジュール）
- 安定版リリース（日時はUTC）
  - 0.31.0（2025-09-08）
  - 0.32.0（2025-09-10）
  - 0.33.0（2025-09-10）
  - 0.34.0（2025-09-10）
- α版（抜粋, 発行順）
  - 0.32.0-alpha.1〜.3（2025-09-08〜09-10）
  - 0.33.0-alpha.1（2025-09-10）
  - 0.34.0-alpha.1〜.2（2025-09-10）
  - 0.35.0-alpha.1〜.10（2025-09-11〜09-15, 最新: alpha.10）
- 特徴
  - 9/8〜9/15にかけて高頻度でα版を連投し、9/10に0.32/0.33/0.34を連続リリース
  - α版での検証→安定版反映の短サイクル運用
  - 「マイルストーン」はオープンなし（計画はIssue/PRとリリースノートで運用）
- 参考: https://github.com/openai/codex/releases

## まとめ（この1ヶ月のトレンド）
- 品質改善とUX向上にフォーカスした小粒PRが高頻度で取り込まれている
- 認証/プロバイダ・パーミッション・ログ連携など運用まわりの安定化が継続テーマ
- リリースは「超短サイクルのα版」→「素早い安定版」というハイテンポ運用
- 明示的な長期ロードマップ/マイルストーンの提示は少なく、Issue/PRでの段階的反映が中心

## 参考リンク
- PR検索（過去30日）: https://github.com/openai/codex/pulls?q=is%3Apr+updated%3A%3E%3D2025-08-15
- Issue検索（過去30日）: https://github.com/openai/codex/issues?q=is%3Aissue+updated%3A%3E%3D2025-08-15
- Discussions: https://github.com/openai/codex/discussions
- Releases: https://github.com/openai/codex/releases
