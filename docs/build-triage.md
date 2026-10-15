# Build/test và báo cáo gọn

Các lệnh quen thuộc tự đi qua `gmaphud-check.py` trên Mac với Python 3.9+:

```sh
sh test.sh
sh test-source-output.sh
sh build-tweak.sh all
# Hoặc chỉ một loại gói:
sh build-tweak.sh rootless
sh build-tweak.sh rootful
```

Công cụ trả `PASS`/`FAIL`, mã thoát, thời gian, số cảnh báo và đường dẫn log. Khi thất bại, nó liệt kê tối đa năm mốc lỗi đầu tiên với nhãn cố định (ví dụ `assertion_failed`, `link_failed`, `process_signal`) và file/dòng trong dự án nếu xác định được. Mọi xử lý diễn ra tại máy; không gọi dịch vụ AI hay API bên ngoài. Các lệnh lồng nhau chỉ tạo một báo cáo cho lượt chạy ngoài cùng.

## Xem toàn bộ output hoặc đổi thời gian chờ

```sh
# Chạy trực tiếp như trước, output đầy đủ, không dùng bộ lọc:
GMAPHUD_CHECK_RAW=1 sh test.sh
GMAPHUD_CHECK_RAW=1 sh build-tweak.sh all

# Đổi giới hạn thời gian cho một lượt (mặc định 900 giây):
python3 gmaphud-check.py build all --timeout 600
```

Nếu chính lượt build/test bị quá thời gian hoặc bị ngắt, runner dừng nhóm tiến trình con do nó tạo: mã `124` cho timeout, `130` cho ngắt. Các ứng dụng và dịch vụ ngoài lượt chạy không bị dừng. Chế độ `GMAPHUD_CHECK_RAW=1` không dùng giới hạn thời gian hay quản lý tiến trình của runner.

## Dữ liệu được lưu

Log đầy đủ nằm riêng tại `~/.config/gmaphud/checks/<lượt-chạy>/full.log`. Thư mục có quyền `0700`, file báo cáo `0600`, ngoài Git và ngoài tweak. Log gốc có thể chứa đường dẫn hoặc thông tin do compiler/test in ra; không tự đăng hay gửi file đó cho dịch vụ bên ngoài.

Các file đi kèm:

- `brief.txt`: kết quả ngắn để đọc trước.
- `evidence.json`: mốc đã nhận diện (nhãn cố định, mức độ, dòng log, file/dòng tương đối trong dự án), số cảnh báo/lỗi và số mốc bị lược bỏ. Không chứa nội dung lỗi tự do hay đường dẫn tuyệt đối.
- `metrics.json`: thời gian, kích thước log gốc và bản tóm tắt.

Parser giữ các mốc đầu và cuối, bỏ dòng dài bất thường và báo số lượng bị bỏ. Lỗi lạ chỉ có nhãn `unrecognized_diagnostic`; cần xem log gốc tại máy.

## Kiểm chứng

`sh test.sh` chạy cả test tweak và test của runner. Có thể chạy riêng, hoàn toàn offline:

```sh
python3 tests/check-runner-tests.py
```

Kích thước log gốc so với bản tóm tắt chỉ cho biết lượng output giảm khi đọc bản ngắn; nó không đo hạn mức hay chi phí của agent. Nếu đọc thêm log gốc, cần tính thêm phần đó.
