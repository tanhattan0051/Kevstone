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
- ✅ **Phase 1 — Engine + bộ test (XONG):** `KeystoneEngine` (Swift thuần) — Telex, Unicode NFC, đặt dấu kiểu mới/cũ, `Syllable` fold, restore-if-invalid, backspace khôi phục dấu. Test **xanh**: 153 ca corpus + 12 property.
- ✅ **Phase 2 — Tầng nhập + menu-bar (XONG, cần nghiệm thu máy thật):** `KeystoneInput` (CGEventTap chạy đúng cách: re-enable trong callback + watchdog 1.5s + self-tag chống đệ quy + không việc nặng trên hot path) + app menu-bar tối thiểu (`App/`). Logic executor/translator/EngineController có **22 unit test xanh**. Quyết định ở [`DECISIONS.md`](DECISIONS.md); CI ở [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
- 🚧 **Phase 3 — Đang làm:** ✅ **VNI** (dùng chung lõi âm tiết với Telex; 33 ca corpus + 8 cặp differential Telex↔VNI xanh). ⬜ Còn: Simple/Quick Telex, 4 bảng mã cũ (TCVN3/VNI-Win/tổ hợp/CP1258), nâng bảng rime §5.3. Xem `HANDOFF.md`.

```
swift build && swift test   # engine + input phải luôn xanh
swift run Keystone          # chạy app menu-bar (cấp quyền Accessibility khi được hỏi)
```

> ⚠️ Gõ tiếng Việt ở mọi app **chỉ chạy trên macOS thật có quyền Accessibility** — `swift run Keystone`, cấp quyền, rồi thử. Xem mục **[VERIFY]** trong `HANDOFF.md`.

## Bản quyền
Engine viết mới từ đầu (clean-room), **không** dùng mã của OpenKey (GPLv3). Bản quyền thuộc tác giả; giấy phép tuỳ chọn.
