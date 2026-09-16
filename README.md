# Keystone

Bộ gõ tiếng Việt cho macOS (26/27) — viết mới hoàn toàn bằng Swift/SwiftUI, tập trung **độ ổn định** (diệt lỗi "đang gõ tự nhiên mất tiếng Việt" của các bộ gõ cũ) và **giao diện hiện đại**.

- 📄 **Thiết kế đầy đủ:** [`docs/superpowers/specs/2026-09-16-keystone-design.md`](docs/superpowers/specs/2026-09-16-keystone-design.md)
- 🧭 **Bắt đầu từ đâu:** đọc [`HANDOFF.md`](HANDOFF.md)
- 🛡️ **Danh mục lỗi cần tránh:** Phần E trong spec
- 🎨 **Icon (đã chốt):** "Gilded K with Coral Wedge" — `Design/AppIcon.appiconset/` (drop vào Xcode)

## Kiến trúc
```
KeystoneEngine  (Swift thuần, thuần logic, test 100%)  — Syllable · Telex/VNI · đặt dấu · chính tả · 5 bảng mã · diff
KeystoneInput   (macOS)  — CGEventTap + watchdog + cache · thực thi "xoá N ký tự, gõ chuỗi X"
Keystone (app)  (SwiftUI) — MenuBarExtra · Bảng điều khiển · Gõ tắt · Chuyển mã · Onboarding
```

## Trạng thái
- ✅ **Thiết kế:** spec + danh mục lỗi + icon đã chốt.
- ✅ **Phase 1 — Engine + bộ test (XONG):** `KeystoneEngine` (Swift thuần) — Telex, Unicode NFC, đặt dấu kiểu mới/cũ, `Syllable` fold, restore-if-invalid, backspace khôi phục dấu. Bộ test Swift Testing **xanh**: 153 ca corpus (8 nhóm) + 12 ca property. Chạy: `swift test`. Quyết định engine ghi ở [`DECISIONS.md`](DECISIONS.md); CI ở [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
- ⬜ **Tiếp theo — Phase 2:** tầng nhập `KeystoneInput` (CGEventTap + re-enable + watchdog + cache) + menu-bar tối thiểu. Xem `HANDOFF.md`.

```
swift build && swift test   # engine phải luôn xanh
```

## Bản quyền
Engine viết mới từ đầu (clean-room), **không** dùng mã của OpenKey (GPLv3). Bản quyền thuộc tác giả; giấy phép tuỳ chọn.
