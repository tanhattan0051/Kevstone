<div align="center">

<img src="Design/icons/AppIcon-1024.png" width="128" alt="Keystone" />

# Keystone

**Bộ gõ tiếng Việt hiện đại cho macOS**

Viết mới hoàn toàn bằng Swift/SwiftUI — tập trung vào **độ ổn định** và **giao diện đẹp**,
diệt tận gốc lỗi kinh điển *"đang gõ tự nhiên mất tiếng Việt"* của các bộ gõ đời cũ.

<br/>

![Platform](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI-1575F9)
![Tests](https://img.shields.io/badge/tests-154%20·%20251%20ca%20corpus-brightgreen)
![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial-orange)
[![CI](https://github.com/tanhattan0051/Kevstone/actions/workflows/ci.yml/badge.svg)](https://github.com/tanhattan0051/Kevstone/actions/workflows/ci.yml)

[Vì sao Keystone](#vì-sao-keystone) ·
[Tính năng](#tính-năng) ·
[Cài đặt](#cài-đặt) ·
[Cấp quyền](#cấp-quyền-hệ-thống) ·
[Kiến trúc](#kiến-trúc) ·
[Lộ trình](#trạng-thái--lộ-trình)

</div>

---

## Vì sao Keystone?

Các bộ gõ tiếng Việt cũ trên macOS hay gặp một lỗi khó chịu: **đang gõ ngon lành thì đột nhiên
mất tiếng Việt**, phải bật/tắt lại mới gõ tiếp được. Nguyên nhân gốc là hệ thống tự tắt event tap
(khi timeout / khi người dùng nhập dồn) mà bộ gõ không bật lại, cộng thêm việc xử lý nặng ngay trên
đường phím nóng (hot path).

Keystone giải quyết bằng **hai lớp phòng thủ** cho vòng đời event tap:

- **Lớp A — tự phục hồi tức thì:** khi macOS gửi `tapDisabledByTimeout` / `tapDisabledByUserInput`,
  Keystone bật lại tap **ngay trong callback**.
- **Lớp B — watchdog dự phòng:** một timer riêng cứ **1.5s** kiểm tra và bật lại tap nếu nó chết —
  đảm bảo tap *không bao giờ* nằm chết.

Cùng với **self-tag** chống xử lý lại chính event mình sinh ra, **không làm việc nặng trên hot path**
(tap chạy trên thread + run loop riêng, tách khỏi UI), và truy cập engine an toàn đa luồng qua
`OSAllocatedUnfairLock`. Đây là những gì làm nên khác biệt của Keystone so với bộ gõ cũ.

---

## Tính năng

### Kiểu gõ & bảng mã

| Kiểu gõ | Trạng thái |
|---|---|
| **Telex** (mặc định) | ✅ Đầy đủ |
| **VNI** | ✅ Đầy đủ |
| Simple Telex 1 / 2 | 🚧 Đang tạm chạy như Telex (xem [lộ trình](#trạng-thái--lộ-trình)) |

- **Quick Telex** *(tuỳ chọn, mặc định tắt):* gõ đúp phụ âm để nở nhanh — `cc→ch`, `gg→gi`,
  `kk→kh`, `nn→ng`, `pp→ph`, `qq→qu`, `tt→th`. Riêng `dd→đ` luôn bật.
- **5 bảng mã đầu ra:** Unicode dựng sẵn *(mặc định)*, Unicode tổ hợp, TCVN3, VNI-Windows, CP1258.
- **Công cụ chuyển mã** văn bản có sẵn (Unicode dựng sẵn ↔ tổ hợp, CP1258 hai chiều; TCVN3 /
  VNI-Windows đang hoàn thiện chiều chuyển ngược).

### Đặt dấu & xử lý thông minh

- **Đặt dấu kiểu mới / cũ** cho các cặp nguyên âm mở `oa`, `oe`, `uy`:
  - Kiểu mới *(mặc định):* `hòa` · `khỏe` · `thủy`
  - Kiểu cũ *(tuỳ chọn):* `hoà` · `khoẻ` · `thuỷ`
- **Khôi phục khi gõ sai** *(mặc định bật):* âm tiết không hợp lệ theo âm vị học sẽ tự trả về đúng
  chuỗi phím thô — nhờ đó gõ từ tiếng Anh như `coins`, `ruins`, `rains` không bị "Việt hoá" nhầm.
- **Khôi phục dấu qua Backspace:** buffer được dựng lại từ phím thô sau mỗi lần gõ (kể cả xoá), nên
  xoá một ký tự dấu rồi gõ lại luôn đúng. Có cả **double-strike undo** (gõ lại phím thanh lần hai để
  bỏ dấu và trả ra ký tự thô).
- **Bỏ dấu tự do** *(mặc định bật):* đặt dấu không cần liền kề chữ — ví dụ `roiof → rồi`.
- **Bỏ dấu cuối từ** *(mặc định bật):* cho dấu vượt qua cả phụ âm cuối — `trene → trên`,
  `dadng → đang`. Đánh đổi có chủ đích: vài từ tiếng Anh (`mama`, `dad`) có thể bị hiểu thành tiếng
  Việt (có cảnh báo trong Bảng điều khiển).
- **Tự viết hoa đầu câu** *(mặc định tắt).*

### Gõ tắt & macro

- **Gõ tắt phụ âm** *(mặc định tắt):* đầu từ `f→ph`, `j→gi`, `w→qu`; sau nguyên âm `g→ng`, `h→nh`,
  `k→ch`.
- **Macro (gõ tắt cụm từ)** *(mặc định tắt):* khớp chính xác, **phân biệt hoa/thường**, nổ đúng lúc
  chốt từ — thắng cả xử lý tiếng Việt lẫn cơ chế khôi phục. Có thể **nhập trực tiếp file macro `.txt`
  của OpenKey** và xuất ra JSON riêng.

### Chuyển chế độ theo ứng dụng

- **Smart-switch** *(mặc định bật):* nhớ & khôi phục trạng thái Việt/Anh **theo từng ứng dụng**.
- **Nhớ bảng mã theo ứng dụng** *(mặc định bật).*
- Nút **"Xoá ghi nhớ theo ứng dụng"** để đặt lại phần đã học.

### Phím tắt & tiện ích hệ thống

- **Phím chuyển Việt/Anh:** `⌃⇧` *(mặc định)*, hoặc `⌥⇧` · `⌘⇧` · `⌃⌥` · Tắt. Nhận diện bằng máy
  trạng thái riêng (ngoài hot path), có phím khác chen vào là huỷ để tránh trùng shortcut.
- **Chỉ báo V/E** ngay trên menu bar.
- **Khởi động cùng macOS** *(mặc định tắt, `SMAppService`)*, **hiện icon trên Dock** *(mặc định
  tắt)*, **mở Bảng điều khiển khi khởi động** *(mặc định tắt)*.
- **Sửa lỗi gợi ý** & **Gửi từng phím** *(mặc định tắt):* né lỗi nhân đôi ký tự ở một số trình duyệt
  / bảng tính.
- **Khoá một phiên bản** (single-instance) tránh chạy trùng gây gõ đôi.

### Bảng điều khiển

Bốn tab: **Cơ bản** (kiểu gõ, bảng mã, tuỳ chọn gõ, quyền) · **Gõ tắt** · **Hệ thống** (khởi động,
cập nhật, hiển thị) · **Thông tin**. Kèm cửa sổ **Công cụ chuyển mã**, trình **soạn gõ tắt**, và
**Onboarding** hướng dẫn cấp quyền.

---

## Cài đặt

Tải bản mới nhất ở trang **[Releases](https://github.com/tanhattan0051/Kevstone/releases/latest)** rồi
làm theo 4 bước:

1. Tải file **`Keystone-<phiên bản>.dmg`**.
2. Mở file DMG vừa tải, **kéo `Keystone.app` vào thư mục `Applications`**.
3. Mở **Keystone** từ Launchpad hoặc thư mục Applications.
4. Khi được hỏi, **cấp quyền Accessibility** (bắt buộc — xem [Cấp quyền](#cấp-quyền-hệ-thống)), rồi
   bật/tắt tiếng Việt bằng chỉ báo **V/E** trên menu bar hoặc phím **⌃⇧**.

> ⚠️ **Bản hiện tại chưa ký (unsigned).** Lần đầu mở, macOS báo *"không xác minh được nhà phát
> triển"* → **chuột phải vào `Keystone.app` → Open** (bấm **Open** lần nữa). Nếu vẫn bị chặn, mở
> **Terminal** và chạy:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Keystone.app
> ```
>
> Yêu cầu: **macOS 14 trở lên**. Bản ký + notarize chính thức (mở là chạy luôn) sẽ có ở các release sau.

---

## Cấp quyền hệ thống

| Quyền | Bắt buộc? | Vì sao |
|---|---|---|
| **Accessibility** | ✅ Bắt buộc | Tạo event tap để chuyển đổi phím ở mọi ứng dụng. Không có → bộ gõ không chạy. |
| **Input Monitoring** | Khuyến nghị | Quan sát phím toàn hệ thống ổn định hơn, tránh rơi phím. |

Cửa sổ **Onboarding** tự mở lần đầu để hướng dẫn cấp quyền; nút "Bắt đầu gõ" / "Để sau" không bao
giờ bị khoá. Nếu cấp quyền xong mà tap chưa tạo được, menu bar sẽ hiện nút **"Khởi động lại
Keystone"**.

---

## Kiến trúc

```
KeystoneEngine  (Swift thuần — logic thuần, phủ test cao)
                Syllable · Telex/VNI · đặt dấu · âm vị học · 5 bảng mã · macro · diff
KeystoneInput   (macOS)  CGEventTap 2 lớp + watchdog + self-tag · executor · smart-switch
Keystone (app)  (SwiftUI) MenuBarExtra · Bảng điều khiển 4 tab · chuyển mã · gõ tắt · onboarding
```

Ba module tách bạch trong một [Swift Package](Package.swift): `KeystoneEngine` không phụ thuộc AppKit
(chạy & test được ở mọi nơi), `KeystoneInput` bọc phần macOS, còn app SwiftUI ghép cả hai. Logic
nghiệp vụ tiếng Việt nằm hết ở tầng engine dưới dạng **hàm thuần** — dễ test, dễ đọc, dễ sửa.

---

## Kiểm thử & CI

- **Engine:** 108 hàm test chạy trên **251 ca corpus tiếng Việt** (11 file JSON: thanh, dấu, đặt dấu,
  vị trí, quick-telex, VNI, regression, khôi phục…).
- **Tầng nhập:** 46 hàm test (translator, executor, engine-controller, phím chuyển, smart-switch).
- **Tổng: 154 hàm test**, tất cả xanh.
- **CI:** [`ci.yml`](.github/workflows/ci.yml) chạy `swift build && swift test` (toàn bộ suite) trên
  `macos-15` cho mỗi push & pull request.

---

## Trạng thái & lộ trình

| Giai đoạn | Tình trạng |
|---|---|
| **1 — Engine + corpus test** | ✅ Xong |
| **2 — Tầng nhập + menu bar** | ✅ Xong *(cần nghiệm thu máy thật)* |
| **3 — Kiểu gõ & bảng mã** (VNI, Quick Telex, 5 bảng mã) | ✅ Xong |
| **4 — Tính năng & UI** (macro, smart-switch, phím chuyển, onboarding, toggle hệ thống) | ✅ Xong *(cần nghiệm thu máy thật)* |
| **5 — macOS 26/27 (Liquid Glass) · ký / notarize / DMG / auto-update** | 🚧 Có script, chờ tài khoản Apple |

**Còn nợ (không chặn):** tách logic riêng cho Simple Telex 1/2 (hiện map về Telex) · chiều chuyển mã
ngược cho TCVN3 / VNI-Windows · bộ kiểm tra bản mới thật (Sparkle) · `spellCheck` (chờ chốt ngữ nghĩa
để không trùng `restoreIfInvalid`).

---

## Giấy phép

Keystone dùng **giấy phép kép (dual-license)**:

- 🆓 **Phi thương mại — miễn phí:** [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0) — cá nhân, học tập, nghiên cứu, dự án phi lợi nhuận được dùng, sửa và chia sẻ thoải mái. Xem [`LICENSE`](LICENSE).
- 💼 **Thương mại:** mọi mục đích kinh doanh cần **giấy phép thương mại riêng** — liên hệ **tanhattan0051@gmail.com** để mua.

Bản quyền © 2026 **Tạ Nhật Tân**.

## Tác giả

**Tạ Nhật Tân** — mọi góp ý xin gửi về **tanhattan0051@gmail.com**.

## Ủng hộ tác giả

Nếu Keystone hữu ích với bạn, đừng quên ủng hộ tác giả bằng cách mời **một ly cà phê hay lon bò húc** ☕🥤

<div align="center">
  <img src="Design/momo-qr.jpg" width="260" alt="Ủng hộ qua MoMo — TA NHAT TAN" />
  <br/>
  <sub>Quét bằng <b>MoMo</b> hoặc app ngân hàng (VietQR · napas 247) — <b>TA NHAT TAN</b></sub>
</div>

Cảm ơn các bạn rất nhiều! 🙏

## Lời cảm ơn

Cảm ơn [**OpenKey**](https://github.com/tuyenvm/OpenKey) của Tuyen Mai — nguồn cảm hứng và là tham
chiếu quý giá về những lỗi thực tế mà một bộ gõ tiếng Việt cần tránh.
