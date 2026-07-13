#!/usr/bin/env bash
#
# make-dmg.sh — sokki.app を Release ビルドし、配布用 dmg に固める。
#
# TASK-10 の決定（初期は無署名で dmg 配布 / Developer ID 取得後に署名+公証へ移行）に従い、
# 既定では一切コード署名を行わない（CODE_SIGNING_ALLOWED=NO）。ad-hoc 署名は
# --adhoc-sign を明示指定した場合のみのオプトイン動作とする。
#
# 外部ツール非依存（hdiutil ベース）。create-dmg（brew）が入っていれば見た目の良い
# dmg を作れるが、本スクリプトは hdiutil のみで完結させる。
#
# Usage:
#   scripts/make-dmg.sh [options]
#
# Options:
#   -o, --output <dir>       dmg の出力先ディレクトリ（既定: ./dist）
#   -v, --version <string>   dmg ファイル名に使うバージョン文字列
#                            （既定: Info.plist の CFBundleShortVersionString）
#   -c, --configuration <c>  xcodebuild の configuration（既定: Release）
#       --adhoc-sign         codesign --force --deep -s - で ad-hoc 署名する
#                            （既定では署名しない。TASK-10 決定＝無署名配布に合わせた既定値）
#       --dry-run            xcodebuild / hdiutil を実行せず、実行するコマンドの
#                            確認のみ行う（Release ビルドが重い環境での動作確認用）
#   -h, --help               このヘルプを表示
#
# 例:
#   scripts/make-dmg.sh --version 0.1.0
#   scripts/make-dmg.sh --output ~/Desktop --dry-run
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="sokki"
SCHEME="sokki"
PROJECT="${REPO_ROOT}/${APP_NAME}.xcodeproj"
INFO_PLIST="${REPO_ROOT}/Info.plist"

OUTPUT_DIR="${REPO_ROOT}/dist"
VERSION=""
CONFIGURATION="Release"
ADHOC_SIGN=0
DRY_RUN=0

usage() {
    # スクリプト冒頭のコメントブロックをそのまま usage として表示する
    sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

log() {
    echo "[make-dmg] $*" >&2
}

fail() {
    echo "[make-dmg] ERROR: $*" >&2
    exit 1
}

run() {
    # DRY_RUN=1 のときはコマンドを表示するだけで実行しない
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "(dry-run) $*"
    else
        log "+ $*"
        "$@"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            [[ $# -ge 2 ]] || fail "--output にはディレクトリを指定してください"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--version)
            [[ $# -ge 2 ]] || fail "--version にはバージョン文字列を指定してください"
            VERSION="$2"
            shift 2
            ;;
        -c|--configuration)
            [[ $# -ge 2 ]] || fail "--configuration には Debug/Release を指定してください"
            CONFIGURATION="$2"
            shift 2
            ;;
        --adhoc-sign)
            ADHOC_SIGN=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "不明なオプション: $1 （--help を参照）"
            ;;
    esac
done

# --- バージョン文字列の決定 ---
if [[ -z "${VERSION}" ]]; then
    if [[ -f "${INFO_PLIST}" ]] && command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
        VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null || true)"
    fi
    if [[ -z "${VERSION}" ]]; then
        VERSION="0.0.0"
        log "バージョン文字列を取得できなかったため既定値 ${VERSION} を使用します"
    else
        log "Info.plist から取得したバージョン: ${VERSION}"
    fi
fi

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

BUILD_DIR="${REPO_ROOT}/.build/dmg-derived-data"
APP_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
STAGING_DIR="${REPO_ROOT}/.build/dmg-staging"

log "APP_NAME=${APP_NAME} VERSION=${VERSION} CONFIGURATION=${CONFIGURATION}"
log "OUTPUT_DIR=${OUTPUT_DIR}"
log "ADHOC_SIGN=${ADHOC_SIGN} DRY_RUN=${DRY_RUN}"

# --- 前提チェック ---
if [[ ! -f "${PROJECT}/project.pbxproj" ]]; then
    if command -v xcodegen >/dev/null 2>&1; then
        log "sokki.xcodeproj が見つからないため xcodegen generate を実行します"
        run xcodegen generate
    else
        fail "sokki.xcodeproj が見つからず、xcodegen も未インストールです。'xcodegen generate' を先に実行してください"
    fi
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    fail "xcodebuild が見つかりません（Xcode Command Line Tools が必要です）"
fi

# --- 1. Release ビルド ---
# TASK-10 の決定に基づき既定では無署名（CODE_SIGNING_ALLOWED=NO）でビルドする。
# Developer ID Program 取得後は、このスクリプトの CODE_SIGN_IDENTITY 周りを
# 署名+公証フローに置き換える想定（docs/distribution.md 参照）。
log "xcodebuild でビルドします（無署名）"
run xcodebuild build \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    | (command -v xcpretty >/dev/null 2>&1 && xcpretty || cat)

if [[ "${DRY_RUN}" -eq 0 ]]; then
    [[ -d "${APP_PATH}" ]] || fail "ビルド後に ${APP_PATH} が見つかりません"
else
    log "(dry-run) ${APP_PATH} の存在チェックはスキップします"
fi

# --- 2. ad-hoc 署名（オプトイン） ---
if [[ "${ADHOC_SIGN}" -eq 1 ]]; then
    log "ad-hoc 署名を行います（--adhoc-sign 指定）"
    run codesign --force --deep --sign - "${APP_PATH}"
else
    log "ad-hoc 署名は行いません（既定。TASK-10 決定＝無署名配布）"
fi

# --- 3. dmg 用ステージングディレクトリの準備 ---
log "ステージングディレクトリを準備します: ${STAGING_DIR}"
run rm -rf "${STAGING_DIR}"
run mkdir -p "${STAGING_DIR}"

if [[ "${DRY_RUN}" -eq 0 ]]; then
    cp -R "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
else
    log "(dry-run) cp -R ${APP_PATH} ${STAGING_DIR}/${APP_NAME}.app"
fi
run ln -s /Applications "${STAGING_DIR}/Applications"

# --- 4. dmg 作成（hdiutil ベース） ---
run mkdir -p "${OUTPUT_DIR}"
run rm -f "${DMG_PATH}"

log "hdiutil で dmg を作成します: ${DMG_PATH}"
run hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

if [[ "${DRY_RUN}" -eq 0 ]]; then
    log "SHA-256: $(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
    log "完了: ${DMG_PATH}"
else
    log "(dry-run) 完了。実際の dmg は生成していません"
fi
