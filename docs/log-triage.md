# Phân loại log GMapHUD bằng Jev

Công cụ thử nghiệm dành cho người hỗ trợ, chạy trên Mac với Python 3.9+. Không nằm trong tweak, không đổi cấu hình iPhone và không tự sửa lỗi. Model cố định là `~typesafe/jev-latest`, gọi [OpenRouter Decisions API](https://openrouter.ai/docs/guides/community/jev). Chi phí được tính trên tài khoản OpenRouter, riêng với hạn mức Codex.

## Đặt API key

1. Tạo key tại [OpenRouter API Keys](https://openrouter.ai/settings/keys). Nên đặt giới hạn chi tiêu nhỏ cho thử nghiệm.
2. Trong thư mục mã nguồn GMapHUD, chạy:

   ```sh
   python3 gmaphud-log-triage.py setup
   ```

3. Dán key vào câu hỏi trong Terminal rồi Enter. Không hiện ký tự là bình thường. Không gửi key vào chat và không ghi key vào câu lệnh.
4. Kiểm tra bằng `python3 gmaphud-log-triage.py key-status`. Lệnh chỉ kiểm tra định dạng/lưu trữ tại máy, chưa xác thực với API.

Key được lưu dạng văn bản riêng tại `~/.config/gmaphud-jev/openrouter-api-key`, quyền `0600`, trong thư mục `0700`, ngoài repository. Chạy `setup` lại để thay key. Công cụ cũng nhận biến môi trường `OPENROUTER_API_KEY` và ưu tiên biến này nếu đã đặt. Không đưa key vào `.env`, mã nguồn hoặc ảnh chụp Terminal. Nếu ngừng dùng, thu hồi key trên OpenRouter và xóa file key tại máy.

Skill chính thức: [TypeSafe skills](https://github.com/typesafe-ai/skills/tree/main/skills/typesafe-ai). Skill giúp thiết kế tích hợp; không tự chuyển các tác vụ Codex sang Jev.

Build/test đã có [luồng tự động riêng](build-triage.md): lệnh thành công trả kết quả gọn, không gọi API; lệnh thất bại có thể nhờ Jev phân loại chẩn đoán đã lọc. Dùng chung key ở trên, không cần chọn file `.txt` cho mỗi lần build/test.

## Dùng với báo cáo người dùng

Nhờ người dùng tái hiện lỗi rồi vào **Cài đặt → GMapHUD → Chẩn đoán / Xuất log** và xuất báo cáo tổng hợp `.txt`. Công cụ không nhận file crash `.ips`/`.crash` hoặc log tùy ý.

Trong thư mục repository, cách dễ nhất là chạy lệnh này rồi nhấn Enter:

```sh
python3 gmaphud-log-triage.py classify
```

Khi thấy lời nhắc, kéo **một file `.txt` từ Finder vào Terminal**, rồi nhấn Enter lần nữa. Đường dẫn có khoảng trắng hoặc dấu nháy được hỗ trợ. Enter trống hoặc Ctrl+C để hủy trước khi gọi API. Không dùng hộp chọn file AppleScript, nên không phụ thuộc thời gian chờ AppleEvent. `preview` cũng hỗ trợ cách nhập này. Nếu chạy từ script không có Terminal tương tác, vẫn cần truyền đường dẫn.

Các lệnh có đường dẫn bên dưới là ví dụ; thay `/đường/dẫn/...` bằng file thật:

```sh
# Chỉ xem ở máy, không gọi API và không cần key:
python3 gmaphud-log-triage.py preview "/đường/dẫn/GMapHUD-diagnostics.txt"

# Gửi các trường đã lọc đến OpenRouter/TypeSafe, một request, không tự retry:
python3 gmaphud-log-triage.py classify "/đường/dẫn/GMapHUD-diagnostics.txt"

# Kiểm tra offline, không cần key:
python3 tests/log-triage-tests.py
```

Chỉ trường đã nhận diện theo cấu trúc báo cáo được gửi: phiên bản app/iOS, mã dòng iPhone (không phải serial), rootless và các mốc hook/nguồn/view. Ngày xuất, đường dẫn, ghi chú tự do, tọa độ, tài khoản và nội dung crash không được chuyển đi. Dòng chẩn đoán lạ chỉ giữ số dòng để kiểm tra ở bản gốc. Báo cáo quá lớn hoặc sai định dạng bị từ chối trước khi gọi API.

Kết quả riêng được lưu dưới `~/.config/gmaphud-jev/reports/`, quyền thư mục `0700`, file `0600`:

- `brief.txt`: phân nhóm sơ bộ, hướng kiểm tra và các mốc chính để đưa cho Codex.
- `evidence.json`: toàn bộ mốc nhận diện được, kèm số dòng và trường chưa đọc được.
- `decision.json`: nhãn, confidence và phân bố xác suất; không chứa key hay phản hồi tùy ý của server.
- `metrics.json`: kích thước đầu vào/đầu ra, độ trễ, model thực tế và usage/cost do API trả về.

Nhóm lỗi gồm thiếu mốc nguồn, dữ liệu nguồn thiếu/hết hạn, hook/cấu trúc gói, nghi vấn bridge/hiển thị, chưa thấy lỗi và chưa đủ bằng chứng. Mốc `Chưa có dữ liệu` không chứng minh ứng dụng bị đóng. Thời gian của mốc log không phải tuổi của mẫu GPS: các mốc không đổi chỉ ghi lại mỗi 10 giây.

Nếu confidence dưới `0.8`, thiếu mục hoặc có dòng chưa nhận diện, công cụ yêu cầu xem bằng chứng. `0.8` là ngưỡng bảo thủ cho thử nghiệm, chưa được hiệu chỉnh trên tập log đủ lớn. Confidence phản ánh phân bố lựa chọn, không phải xác suất chẩn đoán đúng. Ngay cả confidence cao cũng không xác nhận nguyên nhân hay cho phép tự thay đổi máy.

## Cách đánh giá tiết kiệm

So sánh riêng ba mức: báo cáo gốc, bằng chứng đã lọc tại máy và `brief.txt` gửi cho Codex. `jev_request` còn bao gồm câu hỏi/tiêu chí và được tính phí ở OpenRouter. Chi phí đọc log giảm nhờ lọc tại máy phải được tách khỏi giá trị phân loại của Jev.

Metrics luôn có số ký tự và byte UTF-8 thực. Nếu môi trường Python có `tiktoken`, công cụ thêm số token `o200k_base` để so sánh cùng một tokenizer; đây là số đại diện, không phải token tính phí của model Codex hiện tại. Thiếu tokenizer sẽ ghi `null`. Token/cost Jev lấy từ API, không suy từ bảng giá; trường thiếu là không biết, không phải bằng 0.

Để giảm đầu vào thực tế, lần đầu chỉ đưa `brief.txt` cho Codex; đọc thêm `evidence.json` hoặc dòng gốc khi cần. Nếu phải đọc toàn bộ bằng chứng, phải cộng phần đó vào chi phí đầu vào. Một bản tóm tắt ngắn hơn **không chứng minh** đã giảm số lượt reset/hạn mức Codex: còn context cũ, cache, reasoning, tool calls và thời gian xử lý. Một log thật và các ca kiểm tra nhân tạo chỉ là pilot, chưa đủ đo độ chính xác tổng quát.

Không đặt báo cáo người dùng hoặc key trong `docs/`: toàn bộ thư mục này được xuất bản trên GitHub Pages.
