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
Giai đoạn thiết kế xong (spec + danh mục lỗi + concept icon). Chưa viết code triển khai — bắt đầu ở **Phase 1** (engine + bộ test). Xem `HANDOFF.md`.

## Bản quyền
Engine viết mới từ đầu (clean-room), **không** dùng mã của OpenKey (GPLv3). Bản quyền thuộc tác giả; giấy phép tuỳ chọn.
