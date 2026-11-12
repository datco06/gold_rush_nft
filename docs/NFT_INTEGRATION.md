# Tích hợp NFT vật phẩm trong Flutter

`lib/blockchain/vat_pham/nft_service.dart` dùng **PhienVi hiện có**, `Vi` và
`BoGiaoDich`. Service không tạo provider MetaMask, không kết nối ví thứ hai,
không gọi API vàng và không ký phiếu Backend. Không có thay đổi Kho đồ/Gameplay.

## Khởi tạo cho Người 1

Truyền địa chỉ NFT và chain ID từ cấu hình triển khai; không dùng địa chỉ hợp đồng
SBT/cửa hàng làm địa chỉ NFT. Không có địa chỉ Hardhat mặc định trong service.

```dart
import 'package:gold_rush/blockchain/vat_pham/nft_model.dart';
import 'package:gold_rush/blockchain/vat_pham/nft_service.dart';

final nft = DichVuNFT(
  phienVi: phienViHienCo,
  cauHinh: CauHinhNFT(
    chainId: chainIdDaCauHinh,
    hopDong: diaChiNFTDaDeploy,
    tenMang: tenMangDaCauHinh,
    rpcUrl: rpcUrlDaCauHinh,
  ),
);

// Danh mục chỉ chứa metadata. Địa chỉ/chain/tokenId phải đúng cấu hình NFT.
final kiem = VatPhamNFT(
  tokenId: BigInt.one,
  name: 'Kiếm Vàng',
  description: 'Vật phẩm ERC-1155 có thể chuyển nhượng.',
  category: LoaiVatPhamNFT.vuKhi,
  contractAddress: diaChiNFTDaDeploy,
  chainId: chainIdDaCauHinh,
);
await nft.taiDanhSach([kiem]);
```

UI nghe `nft` bằng `ListenableBuilder` hoặc `addListener` và luôn lấy danh sách
mới từ `nft.danhSach`. Kiểm tra `dangTai`, `loiTai` và `verifiedBalance`:

- `verifiedBalance == null`: chưa đọc/xác minh cho phiên hiện tại; không suy ra 0.
- `verifiedBalance == BigInt.zero`: đã đọc và ví không có bản nào.
- `owned`: chỉ true với số dư dương đã đọc trên đúng ví/mạng/hợp đồng.

Service bỏ xác minh khi nhận sự kiện đổi ví/chain hoặc `PhienVi.diaChi` thay đổi,
rồi tự tải lại danh mục. Mạng sai không tự mở hộp thoại khi tải dữ liệu. Nếu đổi
tài khoản trong MetaMask làm PhienVi ngắt kết nối, người chơi kết nối lại bằng
luồng hiện có trước khi tải NFT của ví mới. Kết quả RPC thuộc phiên cũ bị loại bỏ,
kể cả đổi mạng đi rồi về trong lúc đọc. Model đã trả về là ảnh chụp bất biến:
service không thể sửa một tham chiếu model cũ mà UI tự giữ riêng.

Gọi `nft.dispose()` khi không dùng nữa, **trước** khi dispose PhienVi. PhienVi
vẫn thuộc vòng đời ứng dụng; service không dispose phiên ví hoặc provider.

## Các phương thức công khai

| Phương thức | Kết quả |
| --- | --- |
| `docSoDu(BigInt tokenId)` | `BigInt` từ `balanceOf` cho ví hiện tại |
| `docSoDuBatch(List<BigInt> tokenIds)` | Số dư cùng thứ tự đầu vào, qua `balanceOfBatch` |
| `docThongTinVatPham(BigInt tokenId)` | `registered`, `metadataUri`, `maxSupply`, `totalMinted` thực tế |
| `taiVatPham(VatPhamNFT metadata)` | Model mới với số dư, ví, URI và cap đã đọc từ chuỗi |
| `taiDanhSach(List<VatPhamNFT> metadata)` | Ghi nhớ danh mục, tải batch số dư và đọc metadata on-chain |
| `lamMoi()` | Đọc lại danh mục hiện tại; không dùng cache làm bằng chứng |
| `nhanVatPham(metadata, phieu: ...)` | Gửi `claimItem`, chờ receipt, đọc lại số dư, kiểm tra nonce |
| `chuyenVatPham(tokenId: ..., nguoiNhan: ..., amount: ...)` | Chuyển từ ví hiện tại bằng `safeTransferFrom`, chờ receipt, đọc lại số dư hai ví |
| `docBienLai(String hash)` | Theo dõi giao dịch sau timeout/đổi phiên; không gửi lại |

`taiVatPham` là lời gọi đọc độc lập. Để nhận danh sách tự tải lại khi đổi ví/mạng,
UI dùng `taiDanhSach` và nghe service. Danh sách trả về không sửa được từ bên ngoài.

Hợp đồng không lưu tên, mô tả, ảnh hay category; các trường đó do danh mục/Backend
cung cấp. Service chỉ đọc URI từ chuỗi, không tự tải nội dung JSON/IPFS. Loại chưa
đăng ký có URI/cap trong model bằng null, không gọi `uri` để tránh revert. Không
tự dò toàn bộ token ID vì hợp đồng không có hàm liệt kê. `totalMinted` là API tổng
cung thực tế của hợp đồng; không giả định có `totalSupply`.

## Nhận phiếu từ Người 5

Người 5 cấp `PhieuVatPhamDaKy` từ adapter của API thật. Không có endpoint mặc định.
Struct phải khớp chính xác thứ tự/kiểu:

```text
PhieuVatPham(address player,uint256 tokenId,uint256 amount,bytes32 nonce,uint256 deadline)
Domain: name=GoldRushEquipment, version=1, chainId=<mạng>, verifyingContract=<NFT>
```

`tokenId`, `amount`, `deadline` dùng `BigInt`; JSON ghi chuỗi thập phân, nhất là
giá trị vượt `2^53−1`. `nonce` là bytes32 hex `0x` + 64 ký tự, duy nhất toàn hợp
đồng; `chuKy` là ECDSA 65 byte `0x` + 130 ký tự. Deadline tính bằng giây Unix.

```dart
final daKy = PhieuVatPhamDaKy(
  phieu: PhieuVatPham.fromJson(duLieuPhieuTuAdapter),
  chuKy: chuKyTuAdapter,
  cauHinh: cauHinhNFTCuaPhieu,
);
final result = await nft.nhanVatPham(
  kiem,
  phieu: daKy,
  khiDaGui: (hash) { /* lưu hash để theo dõi */ },
  khiCapNhat: (status) { /* hiển thị tiến độ */ },
);
// result: transactionHash, receipt, vatPham đã đọc lại từ Blockchain.
```

Service kiểm tra ví nhận, ID, mạng, hợp đồng và EIP-712 domain thực tế. Deadline,
chữ ký, signer hiện tại, nonce và cap được kiểm bằng mô phỏng `claimItem` trên
node; không dùng đồng hồ thiết bị để kết luận phiếu hết hạn. Hợp đồng xác minh
lại khi giao dịch vào khối. Có phiếu sai thì không được mint; không có cơ chế tự
ký hay tự cấp phiếu trong Flutter.

## Chuyển vật phẩm

```dart
final result = await nft.chuyenVatPham(
  tokenId: kiem.tokenId,
  nguoiNhan: diaChiViNhan,
  amount: BigInt.one,
  // Không cần metadata nếu token đã có trong taiDanhSach.
  metadata: kiem,
  khiDaGui: (hash) { /* lưu hash */ },
);
final soDuViGui = result.vatPham.verifiedBalance;
final soDuViNhan = result.soDuNguoiNhan;
```

Service kiểm tra địa chỉ khác zero, người nhận khác ví gửi, amount/ID uint256
dương và số dư thực tế. Ví hiện tại là cả `from` lẫn người gửi giao dịch; không
có quyền owner/operator, không tự `setApprovalForAll`. Hợp đồng kiểm tra receiver
ERC-1155 bằng mô phỏng và khi thực thi. Bước này chỉ hỗ trợ chuyển đơn; không có
`safeBatchTransferFrom` hoặc logic trang bị/sát thương/phòng thủ.

## Receipt, timeout và lỗi

`trangThai` phân biệt: chờ xác nhận ví, chờ chuỗi, receipt đã xác nhận, thành công,
từ chối, revert, timeout và dữ liệu chưa cập nhật. `transactionHash` chỉ là bằng
chứng đã gửi, không phải thành công. `KetQuaGiaoDichNFT` chỉ trả sau receipt thành
công và đọc/đối chiếu lại số dư. Cùng một PhienVi chỉ xử lý một thao tác ghi.

Lỗi ví dùng `LoiVi`/`LoaiLoiVi` hiện có. `LoiNFT.nguyenNhan` phân biệt chưa kết
nối, sai mạng, cấu hình, chưa sở hữu, thiếu số dư và dữ liệu RPC không hợp lệ.
Lỗi thao tác được bọc bằng `LoiGiaoDichNFT`, giữ `loiGoc`, `transactionHash` và
`receipt` (nếu có), để UI không mất dấu giao dịch đã gửi. Custom error NFT/ERC-1155
được dịch riêng, không diễn giải số dư vật phẩm thành “vàng”.

Sau timeout, không tự gửi lại và service chặn thêm thao tác ghi cho đến khi
`docBienLai(hash)` thấy receipt. Sau đó gọi `lamMoi`. Không suy ra giao dịch tăng
tốc thành công chỉ từ số dư: giao diện Vi hiện tại chưa có API tìm replacement
hash. Nếu MetaMask thay hash, truyền hash mới để đọc receipt và tạo lại service
cho phiên sau khi đã xác minh giao dịch cũ; không bấm gửi lại mù quáng.

Receipt thành công nhưng RPC chưa phản ánh số dư, hoặc có giao dịch đồng thời
làm số dư không đối chiếu được, sẽ trả `duLieuChuaCapNhat` và lỗi giữ receipt thành
công. Đây không phải revert; làm mới dữ liệu trước khi quyết định thao tác khác.

## Kiểm tra

Từ `gold_rush/`:

```bash
dart format lib/blockchain/vat_pham/nft_service.dart test/blockchain/vat_pham/nft_service_test.dart test/blockchain/vat_pham/nft_web_test.dart
flutter analyze --no-pub lib/blockchain/vat_pham test/blockchain/vat_pham
flutter test --no-pub test/blockchain/vat_pham
flutter test --no-pub
```

Fixture ABI sinh bằng viem từ artifact đã compile, đối chiếu calldata từng byte:

```bash
node test/blockchain/vat_pham/sinh_mau_viem.mjs
```

Kiểm tra Web với node Hardhat riêng, không reset node đang dùng cho demo:

```bash
# Terminal 1, trong gold_rush_chain; dùng Node 22.
npx hardhat node --hostname 127.0.0.1 --port 18545

# Terminal 2, trong gold_rush; dùng Node 22 cho bước chuẩn bị.
node test/blockchain/vat_pham/chuan_bi_web.mjs /private/tmp/goldrush-nft-web.json
flutter test --no-pub --platform chrome test/blockchain/vat_pham/nft_web_test.dart \
  --dart-define-from-file=/private/tmp/goldrush-nft-web.json
```

Provider thử nghiệm EIP-1193 đi qua **vi_web.dart thật** và RPC Hardhat thật;
đây không phải tiện ích MetaMask thật. Tài khoản thử được node mở khóa; Backend
giả lập ký phiếu trong script Node chuẩn bị, không ký ở Flutter. Mỗi lần chạy
Web tạo fixture/hợp đồng mới để không tái dùng nonce của lần trước.

Người 5 còn cần: xác minh điều kiện thưởng, quản lý signer/nonce/deadline, cấp
phiếu EIP-712 đúng domain và cung cấp danh mục/metadata thật. Gameplay/Backend
quyết định trạng thái trang bị; sở hữu NFT không đồng nghĩa đã trang bị.
