---
id: TASK-3
title: xcodegen生成時のentitlements空化バグを修正
status: Done
assignee: []
created_date: '2026-07-11 16:34'
labels:
  - Phase1
  - bug
  - infra
milestone: m-0
dependencies: []
references:
  - 'commit:90c111c'
modified_files:
  - project.yml
  - .gitignore
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
xcodegen generateがsokki.entitlementsを空で上書きしてしまう問題を修正。project.ymlのsokki targetにentitlements.properties（audio-input / screen-capture / network.client）を明記し、生成のたびに権限が消える恒久バグを解消した。codexがxcodegen --only-plistsで3権限の保持をレビュー・検証済み。
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
project.ymlにentitlements.properties明記で恒久修正。.gitignoreに.DS_Store追加。codexが実検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
