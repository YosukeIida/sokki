---
id: TASK-4
title: 録音音声をディスクへ保存（.m4a / .wav）
status: Done
assignee: []
created_date: '2026-07-11 16:34'
updated_date: '2026-07-11 17:37'
labels:
  - Phase1
milestone: m-0
dependencies: []
references:
  - 'https://github.com/YosukeIida/sokki/issues/23'
  - 'commit:48f75f5'
modified_files:
  - Sources/SokkiKit/Audio/AudioFileWriter.swift
  - Sources/SokkiKit/Audio/AudioCaptureManager.swift
  - Sources/SokkiKit/Session/SessionManager.swift
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AudioCaptureManagerにAVAudioFile writerを追加し、マイク録音を実ファイル化する。SessionModel.audioFilePathが実体を指すようにする。GitHub Issue #23 (P1-1) 対応。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 停止後にディスク上へ音声ファイル（.wav=16bit PCM または .m4a=AAC）が存在すること
- [x] #2 SessionManager.audioURL(forSessionID:)で実ファイルパスが取得できること
- [x] #3 音声スレッドの書き込みがNSLockで直列化され、close処理が冪等であること
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AudioFileWriter.swiftを新規実装（.wav=16bit PCM / 他=AAC(.m4a)、NSLockで直列化、close冪等）。AudioCaptureManagerのstartCapture(mode:outputURL:)で書き出し配線。SessionManager.audioURL(forSessionID:)追加。Phase1AudioSaveTests.swift（7テスト）で検証。GitHub #23は実装済みだが未クローズ。
<!-- SECTION:FINAL_SUMMARY:END -->
