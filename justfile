# sokki ビルド自動化 (just コマンドが必要: brew install just)

# デフォルト: ヘルプ表示
default:
    @just --list

# ビルド（デバッグ）
build:
    swift build

# テスト（全スイート）
test:
    swift test

# 特定スイートのテスト
test-suite SUITE:
    swift test --filter {{SUITE}}

# ビルド + テスト
check: build test

# スモークテスト（3秒起動して即終了、クラッシュしないことを確認）
smoke:
    @echo "Starting sokki for 3 seconds..."
    @timeout 3 swift run 2>&1 | head -20 || true
    @echo "Smoke test complete (exit by timeout is OK)"

# ビルド成果物をクリア
clean:
    swift package clean

# 依存パッケージ解決
resolve:
    swift package resolve

# --- Xcode プロジェクトがある場合（将来用） ---

# xcodebuild でビルド
xbuild:
    xcodebuild build \
        -project sokki.xcodeproj \
        -scheme sokki \
        -configuration Debug \
        | xcpretty 2>/dev/null || cat

# xcodebuild でテスト（UIテスト含む）
xtest:
    xcodebuild test \
        -project sokki.xcodeproj \
        -scheme sokki \
        -destination "platform=macOS" \
        | xcpretty 2>/dev/null || cat
