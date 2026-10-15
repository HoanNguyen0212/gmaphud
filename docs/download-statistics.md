# Thống kê tải qua nguồn Sileo/Zebra

Nguồn proxy: **https://gmaphud.caidat.app/**. Địa chỉ Cloudflare độc lập: https://gmaphud-downloads.pages.dev/. Nguồn cũ https://bechou0410.github.io/gmaphud/ tiếp tục phục vụ tải/cập nhật.

## Thêm nguồn

Trong Sileo/Zebra, đổi nguồn GMapHUD sang URL proxy; giữ nguyên tweak và các tùy chọn. Tránh thêm đồng thời hai nguồn cùng package để client không chọn ngẫu nhiên đường tải. Người giữ nguồn cũ tiếp tục cập nhật, nhưng lượt tải đi thẳng nguồn cũ không được đếm.

Proxy lấy index và gói từ GitHub Pages đang chạy. `Filename: pool/...` không đổi; Sileo/Zebra dùng hostname nguồn mới để tải gói qua proxy. Phát hành gói theo quy trình hiện tại; không cần deploy lại proxy cho mỗi phiên bản. Template và trình tạo trang tiếng Việt/Anh dùng tên miền mới cho nút thêm Sileo/Zebra và sao chép, đồng thời giữ link GitHub Pages dự phòng. Proxy không thay URL trong HTML nên giữ nguyên link dự phòng.

## Số liệu và giới hạn

D1 lưu ngày theo UTC+7, phiên bản, kiến trúc và tổng yêu cầu. GET đầy đủ của file `.deb` GMapHUD hợp lệ được kiểm tra bằng HEAD ở nguồn; HTTP 200 mới tăng đếm và trả 307 về file gốc. Proxy không truyền nội dung gói, tránh lỗi/chậm qua lớp stream trung gian. Đây là yêu cầu bắt đầu tải file đang có, không chứng minh client theo redirect, tải hoàn tất hay cài thành công. Tải lại, cập nhật, bot và tải kiểm thử có thể tăng số liệu. Không phân biệt Sileo/Zebra bằng User-Agent; không lưu IP, cookie hay định danh thiết bị. Cloudflare/GitHub có chính sách dữ liệu hạ tầng riêng.

HEAD và mọi yêu cầu Range trả 307 về đúng file GitHub Pages, giữ phương thức/header của client và không đếm. Kiểm thử thật phát hiện Cloudflare có thể nén upstream khiến range lệch byte nếu proxy trực tiếp; redirect tránh lỗi đó. Byte gói sau redirect được đối chiếu SHA-256 cả rootful/rootless. Conditional GET vẫn chuyển validator về nguồn; 304 không đếm.

Ghi D1 chạy bất đồng bộ qua `waitUntil`; lỗi/hết hạn mức D1 không chặn tải. Fetch nguồn lỗi mạng, chờ quá 3 giây hoặc 5xx trả 307 về file gốc. Pages production và preview đặt `fail_open=true`: khi hết hạn mức Functions, lớp tĩnh [build-proxy.py](../download-proxy/build-proxy.py) trả redirect về nguồn hiện tại qua `_redirects`. Không cần mirror gói hay index, nên đường dự phòng luôn theo bản phát hành hiện tại. `/__fallback/<path>` bỏ qua Function để kiểm chứng lớp redirect. Sự cố DNS hoặc toàn bộ Cloudflare vẫn cần dùng URL GitHub Pages độc lập.

Theo [hạn mức Functions](https://developers.cloudflare.com/pages/functions/pricing/), Workers Free có 100.000 yêu cầu/ngày dùng chung tài khoản. [D1 Free](https://developers.cloudflare.com/d1/platform/pricing/) có 100.000 rows written/ngày; upsert có thể tính nhiều hơn một row written. Không nâng cấp trả phí trong rollout. OAuth hiện không đọc được subscriptions (403), nên chưa xác minh gói billing của tài khoản; thiết kế dùng các dịch vụ/hạn mức có gói miễn phí.

## Vận hành và triển khai

Cloudflare account ID `d62577f0807884d8befc91d52c72e191`; Pages project `gmaphud-downloads`; D1 database/binding nằm trong [wrangler.jsonc](../download-proxy/wrangler.jsonc). UUID không phải credential. Đăng nhập bằng `wrangler login`; OAuth lưu trong user config, không trong repo. DNS: CNAME `gmaphud.caidat.app` → `gmaphud-downloads.pages.dev`, proxied. Wrangler OAuth không có quyền DNS; quản lý record qua dashboard zone `caidat.app`. Không thay đổi GitHub Pages CNAME/source.

Từ checkout:

```sh
wrangler whoami
node --test tests/download-proxy-tests.mjs
python3 download-proxy/build-proxy.py
wrangler pages deploy download-proxy/pages-output --project-name gmaphud-downloads --branch main --commit-dirty=true
```

Production đã gắn binding DB; không deploy cấu hình thiếu DB. [Schema](../download-proxy/schema.sql) tạo bảng nếu chưa tồn tại, không xóa lịch sử:

```sh
wrangler d1 execute gmaphud-downloads --remote --file download-proxy/schema.sql --config download-proxy/wrangler.jsonc
```

Kiểm tra project Settings → Runtime → Fail open/closed sau thay đổi hạ tầng; production và preview phải giữ fail open. Không bật log request trong Functions để lưu thông tin client. Không có endpoint thống kê công khai; đọc bằng quyền Cloudflare:

```sh
wrangler d1 execute gmaphud-downloads --remote --config download-proxy/wrangler.jsonc --command "SELECT day, version, architecture, requests FROM download_counts ORDER BY day DESC, version, architecture"
wrangler d1 execute gmaphud-downloads --remote --config download-proxy/wrangler.jsonc --command "SELECT version, architecture, SUM(requests) AS requests FROM download_counts GROUP BY version, architecture ORDER BY version, architecture"
```

Có thể cộng số này với `.deb` download_count của GitHub Releases để tổng hợp hai đường đã đo, vẫn thiếu tải trực tiếp nguồn Pages cũ. Không cộng lượt lấy index vào lượt tải gói. Rollout có lượt tải kiểm thử thật; baseline ghi trong báo cáo triển khai, không xóa số liệu âm thầm.

Kiểm tra quota fallback bằng preview riêng, không đốt hạn mức tài khoản:

```sh
python3 download-proxy/build-proxy.py --static-only
wrangler pages deploy download-proxy/pages-fallback-check --project-name gmaphud-downloads --branch fallback-check --commit-dirty=true
```

Preview này không chạy Function; root, Packages và pool phải trả 307 tới đúng đường GitHub Pages, tải theo redirect phải đúng checksum. Đây là kiểm chứng lớp dự phòng khi bỏ qua Function, không phải thử làm cạn quota thực tế.

## Rollback

Đổi nguồn client về https://bechou0410.github.io/gmaphud/. Giữ proxy chạy trong thời gian chuyển để không làm hỏng nguồn đã thêm. Có thể deploy bản `--static-only` lên branch `main` để toàn bộ nguồn mới redirect về GitHub Pages mà không chạy thống kê; giữ database. Không xóa gói đã phát hành. Khôi phục proxy bằng các lệnh production ở trên. DNS/chứng chỉ có thể cần thời gian cập nhật; không tháo hostname đang được client dùng trước khi chuyển nguồn.
