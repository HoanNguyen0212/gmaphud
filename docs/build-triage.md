# Build/test và Jev

Các lệnh quen thuộc tự đi qua `gmaphud-check.py` trên Mac với Python 3.9+:

```sh
sh test.sh
sh test-source-output.sh
sh build-tweak.sh all
# Hoặc chỉ một loại gói:
sh build-tweak.sh rootless
sh build-tweak.sh rootful
```

Khi thành công, công cụ trả `PASS`, thời gian, số cảnh báo và đường dẫn log. **Không đọc key, không gọi API**. Các lệnh lồng nhau chỉ tạo một báo cáo cho lượt chạy ngoài cùng.

Khi thất bại và có chẩn đoán, công cụ gọi Jev tối đa một lần để gợi ý nhóm lỗi: cú pháp, kiểu/API, phụ thuộc/toolchain, linker, test, đóng gói hoặc chưa rõ. Codex vẫn cần kiểm tra bằng chứng trước khi sửa. Jev không thực thi lệnh, không thay đổi mã nguồn và không quyết định pass/fail. Dù Jev lỗi mạng, thiếu key, trả dữ liệu sai hoặc bị hủy trong lúc phân loại, mã thoát của lệnh đã chạy vẫn được giữ nguyên.

Dùng key và model `~typesafe/jev-latest` đã thiết lập trong [hướng dẫn Jev](log-triage.md). Không có key thì vẫn build/test bình thường; khi lỗi, công cụ giữ báo cáo ở máy để đọc thủ công. Chi phí phân loại được tính riêng trên OpenRouter và hiện trong kết quả khi API cung cấp.

## Tắt API hoặc xem toàn bộ output

```sh
# Vẫn có báo cáo gọn, hoàn toàn không gọi Jev:
GMAPHUD_JEV=off sh test.sh
GMAPHUD_JEV=off sh build-tweak.sh all

# Chạy trực tiếp như trước, output đầy đủ, không dùng bộ lọc/Jev:
GMAPHUD_CHECK_RAW=1 sh test.sh
GMAPHUD_CHECK_RAW=1 sh build-tweak.sh all

# Đổi giới hạn thời gian cho một lượt (mặc định 900 giây):
python3 gmaphud-check.py build all --timeout 600
```

Nếu chính lượt build/test bị quá thời gian hoặc bị ngắt, runner dừng nhóm tiến trình con do nó tạo: mã `124` cho timeout, `130` cho ngắt. Không gọi Jev trong hai trường hợp này. Các ứng dụng và dịch vụ ngoài lượt chạy không bị dừng. Chế độ `GMAPHUD_CHECK_RAW=1` không dùng giới hạn thời gian hay quản lý tiến trình của runner.

## Dữ liệu được gửi và lưu

Log đầy đủ nằm riêng tại `~/.config/gmaphud-jev/checks/<lượt-chạy>/full.log`. Thư mục có quyền `0700`, file báo cáo `0600`, ngoài Git và ngoài tweak. Log gốc có thể chứa đường dẫn hoặc thông tin do compiler/test in ra; không tự đăng hay gửi file đó cho dịch vụ bên ngoài.

Jev chỉ nhận loại tác vụ, mã thoát và tối đa 40 mốc đã lọc: loại lỗi theo danh sách cố định, mức độ, số dòng trong log, cùng tên file tương đối/dòng mã nếu xác định được file trong dự án. Nội dung lỗi tự do, đoạn mã nguồn, câu lệnh, đường dẫn tuyệt đối, biến môi trường và API key không được đưa vào dữ liệu phân loại. API key chỉ dùng xác thực request OpenRouter; runner bỏ `OPENROUTER_API_KEY` khỏi môi trường tiến trình build/test con.

Các file đi kèm:

- `brief.txt`: kết quả ngắn để Codex đọc trước.
- `evidence.json`: mốc đã nhận diện, số cảnh báo/lỗi và số mốc bị lược bỏ.
- `jev.json`: trạng thái gọi, lựa chọn/confidence, usage/cost nếu có. Thành công ghi `not_needed_success`.
- `metrics.json`: thời gian, kích thước log gốc và bản tóm tắt.

Parser giữ các mốc đầu và cuối, bỏ dòng dài bất thường và báo số lượng bị bỏ. Lỗi lạ chỉ có nhãn `unrecognized_diagnostic`; cần xem log gốc tại máy. Confidence dưới `0.8` được nhắc kiểm tra thêm; confidence cao cũng không xác nhận nguyên nhân. Không có chẩn đoán nào thì bỏ qua API.

## Kiểm chứng

`sh test.sh` chạy cả test tweak và hai bộ test công cụ Python. Có thể chạy riêng, hoàn toàn offline:

```sh
python3 tests/check-runner-tests.py
python3 tests/log-triage-tests.py
```

Đo log gốc và bản tóm tắt cho biết lượng output có thể giảm khi Codex chỉ đọc bản ngắn. Phần giảm này đến từ bộ lọc cục bộ; Jev hỗ trợ phân nhóm lỗi khi cần. Nó không đo hạn mức Codex, reasoning, cache hay số lần reset. Nếu đọc thêm log gốc, cần tính thêm phần đó. Chi phí API Jev là khoản riêng, không được coi là lượng Codex đã tiết kiệm.
