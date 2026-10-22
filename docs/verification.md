# Kết quả kiểm tra

Kiểm tra ngày 21/10/2026 trên .NET SDK 10.0.300 và Flutter 3.47.4 / Dart 3.13.3.

| Kiểm tra | Kết quả |
|---|---|
| `dotnet build server/Attendance.Api` | Thành công, 0 cảnh báo, 0 lỗi |
| `python3 server/Attendance.SmokeTests/run.py` | 26 kiểm tra tích hợp đạt; SQLite và email tạm được xóa sau khi chạy |
| `flutter analyze --no-pub` | Không có lỗi/cảnh báo lint |
| `flutter test --no-pub --dart-define=CAPTURE_PREVIEWS=true` | 7 kiểm thử đạt, gồm dựng ảnh đăng nhập và ba vai trò ở kích thước 430 × 932 |
| `flutter build apk --debug --no-pub` | Thành công; APK tại `mobile/build/app/outputs/flutter-apk/app-debug.apk`, API mặc định `http://10.0.2.2:5099` dành cho Android Emulator |

Đã xem ảnh giao diện đăng nhập, sinh viên và giáo viên để kiểm tra bố cục. Ảnh sử dụng dữ liệu mẫu từ HTTP giả lập, không phải ảnh chụp thiết bị Android.

Máy chủ tích hợp dùng email pickup trong Development. **Chưa gửi thử SMTP ra hộp thư thật** vì chưa có cấu hình tài khoản email của người dùng.

**Chưa kiểm thử cảm biến trên điện thoại thật**: GPS/quyền vị trí, camera QR/OCR, NFC, sinh trắc học và micro/nhận giọng nói. Kiểm thử API xác nhận quy tắc máy chủ và dữ liệu đầu vào; không thay thế thử nghiệm phần cứng. Luồng sinh trắc học chưa có bằng chứng ký từ phần cứng cho máy chủ.

Các bước thử trên thiết bị: xem [README](../README.md), phần “Kịch bản sử dụng” và “Phạm vi và giới hạn”.

## Cập nhật gửi OTP qua Gmail

- Build API đã cập nhật: thành công, 0 cảnh báo, 0 lỗi (build và kiểm thử từ bản sao tại `/private/tmp` để tránh lỗi đọc tệp trong workspace).
- Kiểm thử tích hợp API: **27 kiểm tra đạt**, gồm phản hồi phân biệt SMTP và email thử nghiệm lưu cục bộ.
- Kiểm thử Flutter `test/app_test.dart`: **7 kiểm thử đạt**, gồm thông báo đúng khi chuyển từ email thử nghiệm sang SMTP.
- Phân tích mã Flutter: không có vấn đề.
- Công cụ cấu hình Gmail: **6 kiểm thử đạt** cho chuẩn hóa dữ liệu, TLS trước xác thực, không gửi thư thử, quyền tệp bí mật `0600`, nhận mật khẩu từ hộp thoại và hủy nhập. Hộp thoại có nút **Dán**, đã biên dịch thành công bằng `osacompile` trên macOS.
- Bản Android đã build, cài và mở lại trên điện thoại NX669J; API được khởi động lại để tự nạp `App_Data/smtp.local.json` khi cấu hình được lưu.

Đã mở trang tạo mật khẩu ứng dụng Google và Terminal nhập thông tin riêng trên máy. **Còn chờ người dùng nhập Gmail gửi mã và mật khẩu ứng dụng; chưa xác nhận gửi thư thật tới hộp thư.** Công cụ chỉ lưu cấu hình sau khi đăng nhập SMTP thành công. Sau khi lưu, cần yêu cầu một OTP mới từ app.

## Khôi phục kết nối điện thoại qua USB

- API tại `127.0.0.1:5099` vẫn hoạt động; điện thoại NX669J đang kết nối USB nhưng danh sách `adb reverse --list` trống.
- Đã khôi phục bằng `adb -s 0123456789ABCDEF reverse tcp:5099 tcp:5099`.
- Kiểm tra trực tiếp từ điện thoại bằng `curl http://127.0.0.1:5099/health`: **HTTP 200**, phản hồi `{"status":"ok","service":"Attendly API"}`.
- Cấu hình Gmail cục bộ đã được tạo sau bước xác thực SMTP; chưa xác nhận OTP mới tới hộp thư thật. Không đọc nội dung bí mật khi kiểm tra kết nối.

## Giáo viên đăng nhập không OTP

- Theo yêu cầu của chủ dự án, đã chuyển tài khoản `phongle2302` từ sinh viên sang giáo viên, giữ nguyên mật khẩu và email đã xác thực. Tài khoản chưa có ghi danh lớp; đã thu hồi phiên và OTP cũ, ghi nhật ký thay đổi quyền.
- Giáo viên đã xác thực email nhận phiên đăng nhập sau khi kiểm tra đúng mật khẩu; sinh viên và admin tiếp tục yêu cầu OTP. Luồng đăng ký vẫn xác thực email và không cho tự nâng quyền.
- API build thành công, 0 cảnh báo/lỗi. **33 kiểm tra tích hợp đạt** trên cơ sở dữ liệu tạm, gồm mật khẩu giáo viên sai bị từ chối, giáo viên đăng nhập không tạo OTP, tạo lớp/buổi và cách ly quyền giáo viên.
- Flutter: **8 kiểm thử đạt**, gồm đăng nhập thẳng vào dashboard giáo viên và lưu phiên. `flutter analyze --no-pub`: không có vấn đề.
- APK debug build thành công, địa chỉ API `http://127.0.0.1:5099` qua USB. API đã khởi động lại và `/health` trả trạng thái `ok`.
- Đã cài APK mới lên NX669J (`adb install -r`: `Success`), mở app và khôi phục đường USB. Kiểm tra `/health` trực tiếp trên điện thoại: **HTTP 200**. Chưa thao tác đăng nhập bằng mật khẩu thật của người dùng.

## Bổ sung bản đồ vị trí

- Mã nguồn được cập nhật tại `/Users/lutuanhuy/Desktop/luvinhphong2302` sau khi thư mục dự án được chuyển tên.
- Thêm màn hình OpenStreetMap: chọn tâm lớp và bán kính, định vị GPS theo yêu cầu, xem khoảng cách/vùng điểm danh và vị trí đã ghi nhận trong báo cáo.
- Không tự xin GPS khi mở biểu mẫu tạo buổi; người dùng bấm nút định vị hoặc chọn điểm trên bản đồ. Hủy chọn giữ giá trị biểu mẫu; quyền gửi GPS khi điểm danh giữ luồng đồng ý hiện có.
- Kiểm thử: **15 kiểm thử Flutter đạt** (8 hồi quy và 7 cho bản đồ), gồm lưu tọa độ GPS/bán kính, chọn điểm rồi hủy, lỗi GPS và thử lại, GPS không chính xác, vị trí báo cáo chỉ đọc, lỗi tải nền và thử lại, tọa độ không hợp lệ. Kiểm thử bản đồ dùng ảnh nền trong bộ nhớ và GPS giả lập, không gọi máy chủ bản đồ công cộng.
- Người dùng chọn tự cài APK sau; chưa kiểm thử GPS thật và tải nền bản đồ trên điện thoại cho bản này.
- `flutter analyze --no-pub`: **không có vấn đề**. APK debug build thành công, lưu tại `mobile/build/app/outputs/flutter-apk/app-debug.apk`; mã nguồn và APK đã đối chiếu với bản dùng để kiểm thử. API trong APK là `http://127.0.0.1:5099`, cần máy chủ đang chạy và `adb reverse tcp:5099 tcp:5099` khi dùng qua USB.

## Chỉnh giao diện đăng nhập và đăng ký

- Thiết kế lại hai biểu mẫu với nền xanh đậm, thẻ trắng, tab chuyển chế độ, biểu tượng trường nhập và nút hiện/ẩn mật khẩu. Hỗ trợ gợi ý điền tài khoản, phím chuyển trường và cuộn khi mở bàn phím.
- Đăng ký có xác nhận mật khẩu, kiểm tra email/tên đăng nhập và thông báo lỗi ngay tại trường. Đăng nhập giữ kiểm tra mật khẩu hiện có; giáo viên vào dashboard trực tiếp, sinh viên/admin tiếp tục dùng OTP.
- Làm lại màn hình OTP và thông báo lỗi; tiếp tục phân biệt email SMTP và email thử nghiệm cục bộ. Quay lại hoặc chuyển chế độ đặt lại thông báo lỗi, che mật khẩu và đưa biểu mẫu về đầu trang.
- `flutter analyze --no-pub`: **không có vấn đề**. **19 kiểm thử đạt** gồm hồi quy đăng nhập, bản đồ, đăng ký, xác nhận mật khẩu, bàn phím màn hình 360×740, đổi chế độ và dựng ảnh ba màn hình ở 430×932.
- Đã mở và xem ảnh `docs/previews/auth-login.png`, `auth-register.png`, `auth-otp.png` với dữ liệu giả lập. Không dùng mật khẩu thật để kiểm thử.
- APK debug build thành công, địa chỉ API qua USB `http://127.0.0.1:5099`; lưu tại `mobile/build/app/outputs/flutter-apk/app-debug.apk`. API khởi động từ thư mục dự án hiện tại để dùng dữ liệu và cấu hình Gmail hiện có.
- Đã cài bản mới lên NX669J (`adb install -r`: `Success`), mở `vn.edu.attendly.attendly/.MainActivity` và xác nhận tiến trình đang chạy. Kiểm tra `/health` trực tiếp từ điện thoại: **HTTP 200**. Chưa đăng nhập bằng thông tin thật hoặc gửi OTP thật trong lần kiểm tra giao diện này.

## Đổi định vị sang GPS tự động

- Bản đồ tự lấy vị trí khi mở hoặc khi ứng dụng được tiếp tục sau khi vào cài đặt. Đã bỏ thao tác chọn tọa độ bằng cách chạm bản đồ.
- Khi mở buổi học mới, giáo viên xác định/xác nhận GPS trước khi nhập thông tin buổi học. Tọa độ trong biểu mẫu chỉ đọc; cập nhật bằng kết quả GPS từ điện thoại, không gõ tay. Chỉnh thông tin buổi học cũ vẫn giữ tâm lớp đã lưu nếu không cập nhật GPS.
- Xác nhận vị trí lớp cần GPS có tọa độ hữu hạn/hợp lệ, sai số >0 và ≤50 m, thời gian trong khoảng từ 60 giây trước đến 10 giây sau thời điểm hiện tại. Kiểm tra lại khi bấm xác nhận. Lấy lại GPS thất bại không cho dùng kết quả cũ để xác nhận. Khi bấm điểm danh cũng kiểm tra kết quả GPS trước khi gửi API.
- Có trạng thái đang định vị, thông báo thiếu quyền/tắt GPS/hết thời gian, nút mở cài đặt vị trí/quyền và thử lại. Báo cáo tiếp tục hiển thị vị trí lịch sử, không yêu cầu GPS mới.
- Kiểm thử: **21 kiểm thử đạt** tổng cộng gồm 10 kiểm thử GPS/bản đồ, 8 hồi quy app và 3 biểu mẫu đăng nhập/đăng ký; bài dựng ảnh tùy chọn được bỏ qua. Bộ GPS gồm tự lấy vị trí, không đổi tâm khi chạm, hủy xác nhận, thiếu quyền rồi thử lại, từ chối GPS cũ/sai số lớn, lỗi làm mới, tự lấy lại sau khi quay về từ cài đặt, báo cáo lịch sử và thử tải lại nền.
- Người dùng chọn cài APK sau; chưa kiểm thử cảm biến GPS thật hoặc cấp quyền vị trí trên điện thoại cho thay đổi này.
- `flutter analyze --no-pub`: **không có vấn đề**. APK debug build thành công, đã lưu và đối chiếu mã băm tại `mobile/build/app/outputs/flutter-apk/app-debug.apk`. 5 tệp Flutter được đối chiếu đúng bản đã build/kiểm thử. API trong APK: `http://127.0.0.1:5099`, dùng máy chủ cục bộ qua USB và `adb reverse tcp:5099 tcp:5099`.
