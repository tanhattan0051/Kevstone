# Keystone — HANDOFF / Ghi chú bàn giao

> Đọc file này trước khi code tiếp (kể cả khi mở bằng Claude Desktop). Toàn bộ thiết kế nằm trong `docs/superpowers/specs/2026-09-16-keystone-design.md`.

## Keystone là gì
App **bộ gõ tiếng Việt mới hoàn toàn cho macOS 26/27**, thay thế OpenKey, nhằm **diệt tận gốc lỗi "đang gõ tự nhiên mất tiếng Việt"** và có giao diện đẹp hợp macOS 27. Đây là **dự án của riêng bạn** (Hướng B).

## Các quyết định đã chốt
- **Hướng B:** engine tiếng Việt **viết mới từ đầu (clean-room)** — KHÔNG đọc/chép mã của OpenKey (OpenKey là GPLv3). Nhờ vậy app **thuộc bản quyền của bạn**, tự do chọn giấy phép (kể cả đóng/độc quyền).
- **Tên:** **Keystone** · bundle id `com.tanta.keystone` (đổi được).
- **Công nghệ:** **Swift thuần** cho tất cả (engine + tầng nhập + UI) · **SwiftUI** (phong cách macOS 27, Liquid Glass) · app menu-bar (LSUIElement) · target **macOS 26.0+** (dev trên 27).
- **Cơ chế nhập (v1):** **CGEventTap làm đúng cách** (tương thích mọi app). InputMethodKit để dành v2.
- **Chính tả mặc định:** kiểu mới (oà, uý); kiểu cũ là tuỳ chọn.
- **Phân phối:** Developer ID + notarize + DMG (không lên App Store được vì cần quyền Accessibility). Cập nhật: Sparkle (Phase 5).
- **Giao diện:** **mirror đúng bố cục OpenKey** (menu + Bảng điều khiển 4 tab: Cơ bản / Gõ tắt / Hệ thống / Thông tin) — xem Phần 2 của spec.

## ⚠️ Lỗi phải diệt (quan trọng nhất — xem Phần E của spec)
1. **E.1 — Mất tiếng Việt khi đang gõ (lỗi số 1):** OpenKey không bật lại event tap khi macOS tắt nó + làm việc nặng trên hot path. **Keystone:** xử lý `kCGEventTapDisabledByTimeout/UserInput` ngay trong callback + **watchdog** định kỳ + **không làm gì nặng trong callback** (cache qua notification đổi app).
2. **E.4 — Crash/không phản hồi:** lỗi bộ nhớ CoreFoundation. **Keystone:** dùng bridging CF an toàn của Swift.
3. **E.2/E.3/E.5/E.6…** đúp chữ (Spotlight), kén app (Terminal/Electron), sai hoa/thường, ghép âm sai. Mỗi lỗi đã ánh xạ tới phần thiết kế + phải có test. Danh sách issue thật của OpenKey đã dẫn số `#` trong Phần E.

## Cấu trúc repo
```
docs/superpowers/specs/2026-09-16-keystone-design.md   ← SPEC ĐẦY ĐỦ (đọc cái này)
Design/icons/*.svg                                      ← 5 concept icon + glyph menu-bar
Design/icons/concepts.json                              ← mô tả/palette từng concept
Design/icon-showcase.html                              ← trang xem icon (đã publish)
HANDOFF.md (file này) · README.md
```
Mã nguồn OpenKey để tham chiếu (đọc để hiểu lỗi, KHÔNG chép): `../OpenKey`.

## Icon — ĐÃ CHỐT ✅
- **Đã chọn: "Gilded K with Coral Wedge"** (`monogram-k`) — chữ K vàng + nêm keystone coral + dấu mũ.
- SVG gốc: `Design/icons/AppIcon.svg` · master PNG: `Design/icons/AppIcon-1024.png`
- **`Design/AppIcon.appiconset/`** — đủ 10 kích cỡ + `Contents.json`, kéo thẳng vào `Assets.xcassets` của Xcode.
- Glyph menu-bar (template, đơn sắc): `Design/menubar/menubarTemplate.png` (18px) + `@2x` (36px). Đặt "Render As: Template Image".
- Trang so sánh 5 hướng (tham khảo): https://claude.ai/artifact/PvMAVx1Q5xZRUSEGBiDx8i
- Muốn tinh chỉnh thêm (màu/độ dày nét/bo góc) cứ bảo mình.

## Việc tiếp theo (lộ trình — chi tiết ở Phần D của spec)
- ✅ **Phase 1 — XONG:** module `KeystoneEngine` (Swift thuần) + **bộ test corpus**. Đã có: Telex đầy đủ, Unicode NFC, đặt dấu kiểu mới **và** cũ (Phần A §4), `Syllable` fold (re-derive mỗi phím), restore-if-invalid 2 lớp, backspace khôi phục dấu (Phần A §8). Test Swift Testing **xanh**: 153 ca corpus + 12 property. Các quyết định engine (bao gồm giải Open Questions) ghi ở `DECISIONS.md`. CI: `.github/workflows/ci.yml`.
  - Cấu trúc: `Sources/KeystoneEngine/{Model,NFC,TonePlacement,Phonology,Telex,Engine}.swift`; test + corpus JSON ở `Tests/KeystoneEngineTests/`.
  - Đã diệt tại engine (có regression test): E.5 (hoa/thường theo cấu trúc, `VIEEJT`→`VIỆT`), E.6 (`chưa`+`a`→`chưaa` không ép `chưâ`; `hồng` không `hoồng`; `huơ`/`khuơ`/`thuở` gõ được qua phím `[`; `gì`/`gìn`), và bảo vệ từ tiếng Anh (`wrong`,`coins`,`ruins`…).
  - Còn nợ (Phase 3): bảng rime §5.3 mới ở mức luật offglide (đủ cho v1, nên nâng thành bảng đầy đủ sau); VNI/Simple/Quick Telex; 4 bảng mã cũ (TCVN3/VNI-Win/tổ hợp/CP1258).
- **Phase 2 (bắt đầu ở đây):** `KeystoneInput` (CGEventTap + re-enable + watchdog + cache) + menu-bar tối thiểu → **kiểm các mục [VERIFY]** trên máy thật. Engine đã thuần & test kỹ nên tầng nhập chỉ cần *thực thi* `EngineResult` (xoá N + gõ chuỗi).
- **Phase 3:** VNI, Simple Telex 1/2, Quick Telex + đủ 5 bảng mã.
- **Phase 4:** gõ tắt, smart-switch, công cụ chuyển mã, Bảng điều khiển 4 tab, onboarding.
- **Phase 5:** ký, notarize, DMG, Sparkle.

## ⚠️ [VERIFY] — phải đo trên macOS 27 thật (trước/khi vào Phase 2)
- Event tap **biến đổi** trên macOS 26/27 cần **Accessibility là đủ**, hay **cần thêm Input Monitoring**? (quyết định onboarding 1 hay 2 thẻ quyền)
- Cấp quyền xong **có cần khởi động lại app** không?
- App nào xử lý sai chuỗi Unicode nhiều ký tự (terminal/Electron/JetBrains) → cần fallback gõ từng grapheme.
- Sàn triển khai macOS 26 với SDK đang cài (kiểm toolchain).
- Bảng byte chuẩn cho TCVN3 / VNI-Windows / CP1258 (tự soạn + kiểm chứng).

## Câu hỏi mở còn để ngỏ (xem cuối spec)
Chuẩn hoá y↔i (Mỹ/Mĩ), chính sách auto-`ươ`, UX thanh sai trên âm tiết đóng, macro fire ở đâu trong pipeline, mặc định `zAlsoStripsDiacritics`.
