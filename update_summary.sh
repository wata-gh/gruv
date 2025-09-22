#!/bin/zsh

BASEDIR=`dirname $0`
cd $BASEDIR
codex exec -C . --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "https://github.com/$1/$2 のリポジトリについて直近１ヶ月の開発状況とリリースについてわかりやすい日本語でまとめてください。また、結果を [organization name]_[repository name]_[today's date].md に出力してください。\nフォーマットは以下で issue/discussion/pull-request にはリンクを貼るようにお願いします。\n`cat template.md`"
