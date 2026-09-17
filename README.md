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
- ✅ **Phase 3 — Kiểu gõ & bảng mã (XONG):** VNI + Quick Telex (Simple Telex → dispatch Telex); **5 bảng mã** (Unicode dựng sẵn/tổ hợp, TCVN3, VNI-Windows, CP1258) qua `OutputTable` + `Converter` (byte đã kiểm chứng). Telex đã **rà đối kháng ~800 từ** (thanh, dấu, đ/gi/qu, cấu trúc âm tiết, HOA, backspace) và làm chặt: gõ "bỏ dấu sau" chạy, bảo vệ từ tiếng Anh, xử uơ words.
- 🚧 **Phase 4 — Tính năng & UI:** Bảng điều khiển 4 tab, Công cụ chuyển mã, trình sửa Gõ tắt, khoá single-instance.
  - ✅ **Gõ tắt (macro) — nối engine XONG:** nổ lúc chốt từ theo phím thô, thắng cả rendering tiếng Việt lẫn restore-if-invalid (giải Open Q #9); 2 nhánh (bật/khi tắt tiếng Việt); import được file macro OpenKey (`.txt`).
  - ✅ **Smart-switch — XONG (cần nghiệm thu máy thật):** nhớ & khôi phục VN/English + bảng mã **theo từng app**, chạy theo notification đổi app (off hot-path, E.7); nút "Xoá ghi nhớ theo ứng dụng".
  - ⬜ **Còn:** onboarding + vài toggle phụ (viết hoa đầu câu, gõ tắt phụ âm f→ph/g→ng, phím chuyển, khởi động cùng máy, hiện Dock icon…).
  - **Phase 5** (ký/notarize/DMG) đã có script (`Scripts/`), chờ tài khoản Apple.
- Toàn bộ test **xanh**: ~251 ca engine + **36 ca input**. Quyết định ở [`DECISIONS.md`](DECISIONS.md). Xem `HANDOFF.md`.

```
swift build && swift test   # engine + input phải luôn xanh
swift run Keystone          # chạy app menu-bar (cấp quyền Accessibility khi được hỏi)
```

> ⚠️ Gõ tiếng Việt ở mọi app **chỉ chạy trên macOS thật có quyền Accessibility** — `swift run Keystone`, cấp quyền, rồi thử. Xem mục **[VERIFY]** trong `HANDOFF.md`.

## Tác giả
- **Tạ Nhật Tân**
- Mọi góp ý, gửi cho mình qua **tanhattan0051@gmail.com**

## Bản quyền
Bản quyền thuộc **Tạ Nhật Tân**. Phát hành theo giấy phép **MIT** (xem [`LICENSE`](LICENSE)).
