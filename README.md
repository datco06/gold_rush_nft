# Gold Rush Blockchain

> Trò chơi phiêu lưu 2D kết hợp blockchain, ví Web3, NFT, SBT, phần thưởng QR và mô-đun AI.

Gold Rush là đồ án game Web3 chạy trên Flutter/Flame. Người chơi khám phá bản đồ thế giới, hoàn thành các màn chơi, nhận vàng, sử dụng vật phẩm NFT, nhận huy hiệu thành tích SBT và đổi phần thưởng bằng mã QR.

## Demo và dịch vụ

| Thành phần | Địa chỉ / thông tin |
|---|---|
| Web game | [gold-rush-web.web.app](https://gold-rush-web.web.app) |
| Backend API | [gold-rush-api.onrender.com](https://gold-rush-api.onrender.com) |
| Mạng blockchain kiểm thử | Sepolia, chain ID `11155111` |
| Blockchain local | Hardhat, chain ID `31337` |
| Mã nguồn | [github.com/datco06/gold_rush_nft](https://github.com/datco06/gold_rush_nft) |

> Các dịch vụ demo phụ thuộc vào trạng thái deploy, database và cấu hình môi trường hiện tại. Không dùng tài khoản, private key hoặc dữ liệu thật trong môi trường demo.

## Chức năng chính

- Đăng nhập bằng ví Web3 và xác thực phiên với backend.
- Bản đồ thế giới gồm nhiều màn chơi, mở khóa theo tiến trình.
- Gameplay 2D bằng Flutter Flame: di chuyển, chiến đấu, thu thập vàng và hoàn thành màn.
- Sinh quái theo màn và điều chỉnh nhịp độ để phù hợp trải nghiệm chơi.
- Lưu tiến trình, vàng, nhiệm vụ và kết quả ván chơi trên backend.
- Cửa hàng vật phẩm và kho đồ NFT ERC-1155.
- Đồng bộ số lượng NFT bằng `balanceOfBatch`, hiển thị trạng thái tải khi dữ liệu blockchain chưa sẵn sàng.
- Cấp huy hiệu thành tích dưới dạng SBT ERC-721 có chữ ký EIP-712.
- Faucet Sepolia cho ví thiếu ETH để thực hiện giao dịch ký ví.
- Trung tâm quà tặng: quét mã QR để nhận vàng, giày, giáp hoặc vũ khí.
- Mô-đun AI phục vụ phân tích, sinh dữ liệu và các API hỗ trợ đồ án.
- CI/CD bằng GitHub Actions, Firebase Hosting và Render.

> Tính năng tạo nhân vật bằng AI hiện đang ẩn trong bản build demo. Các test
> trực tiếp cho màn hình Xưởng AI được đánh dấu skip có lý do; các test model,
> schema và API AI độc lập vẫn được giữ lại để kiểm tra contract dữ liệu.

## Kiến trúc tổng quan

```text
+-------------------+       HTTPS        +-----------------------+
| Flutter Web / APK | -----------------> | FastAPI Backend       |
| Flutter + Flame   |                    | Auth, game, rewards   |
+---------+---------+                    +-----------+-----------+
          |                                          |
          | WalletConnect / MetaMask                 | SQLite/PostgreSQL
          v                                          v
+-------------------+                    +-----------------------+
| Ví người chơi     |                    | Database              |
| Sepolia           |                    | User, game, QR codes |
+---------+---------+                    +-----------------------+
          |
          | RPC / signed transaction
          v
+----------------------------------------------------+
| Smart contracts: Store, NFT ERC-1155, SBT         |
| Sepolia / Hardhat local                            |
+----------------------------------------------------+
```

## Cấu trúc thư mục

```text
Gold_Rush_Blockchain_v1.3_2026/
├── gold_rush/                 # Ứng dụng Flutter, Flame và giao diện Web3
├── gold_rush_ai/              # FastAPI backend, AI, database và QR rewards
├── gold_rush_chain/           # Smart contracts Hardhat
├── docs/                      # Tài liệu tích hợp NFT và SBT
├── .github/workflows/         # CI, deploy Firebase và build APK
└── README.md                  # Tài liệu tổng quan dự án
```

Tài liệu chi tiết theo từng phần:

- [Flutter game](gold_rush/README.md)
- [Backend và AI](gold_rush_ai/README.md)
- [Smart contracts](gold_rush_chain/README.md)
- [Tích hợp NFT](docs/NFT_INTEGRATION.md)
- [Tích hợp SBT](docs/SBT_INTEGRATION.md)

## Công nghệ sử dụng

- **Frontend:** Flutter, Dart, Flame, Reown AppKit/WalletConnect.
- **Backend:** Python 3.12, FastAPI, SQLAlchemy, Alembic, SQLite/PostgreSQL.
- **Blockchain:** Solidity, Hardhat, OpenZeppelin, EIP-712, Sepolia.
- **AI/data:** Python, mô-đun AI nội bộ và dữ liệu gameplay.
- **Triển khai:** GitHub Actions, Firebase Hosting, Render.

## Yêu cầu môi trường

- Flutter stable và Dart SDK tương ứng.
- Python 3.12 trở lên.
- Node.js 20+ và npm.
- Git.
- MetaMask hoặc ví Web3 tương thích.
- Sepolia ETH chỉ cần khi chạy các giao dịch on-chain bằng ví người chơi hoặc deploy contract.

## Chạy local

### 1. Smart contracts local

```bash
cd gold_rush_chain
npm ci
npx hardhat compile
npx hardhat test
npx hardhat node
```

Nếu chạy backend/frontend với Hardhat local, dùng chain ID `31337` và RPC mặc định `http://127.0.0.1:8545`.

### 2. Backend FastAPI

```bash
cd gold_rush_ai
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
cp .env.example .env
python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

Các biến môi trường quan trọng được khai báo trong `gold_rush_ai/.env.example`, gồm:

- URL/RPC blockchain và chain ID.
- Địa chỉ các contract cửa hàng, NFT và SBT.
- Cấu hình faucet Sepolia.
- Khóa ký backend cho các luồng đã được ủy quyền.
- Cấu hình database và secret xác thực.

### 3. Flutter Web

```bash
cd gold_rush
flutter pub get
flutter run -d chrome \
  --web-port 5174 \
  --dart-define=GOLD_RUSH_API=http://127.0.0.1:8000
```

Nếu không truyền `GOLD_RUSH_API`, ứng dụng có thể dùng giá trị mặc định trong mã nguồn. Khi test local nên truyền rõ URL backend để tránh gọi nhầm API production.

### 4. Flutter Android

Có thể chạy trên máy ảo Android SDK để thử giao diện và luồng mở MetaMask.
Xem [cấu hình máy ảo và cách chạy Android](gold_rush/README.md#23-chạy-bản-android).
Để dùng chung API demo và Sepolia với người kiểm thử, dùng cùng bộ cấu hình
trong mục [Đóng gói APK thủ công](#đóng-gói-apk-thủ-công).

## Cấu hình blockchain

Hai mạng được sử dụng trong đồ án:

| Mạng | Chain ID | Mục đích |
|---|---:|---|
| Hardhat local | `31337` | Phát triển và kiểm thử contract |
| Sepolia | `11155111` | Demo giao dịch và ký ví |

Các địa chỉ contract phải được cấu hình theo lần deploy tương ứng. Không lấy địa chỉ contract của mạng khác để dùng trên Sepolia.

Ví dụ nhóm biến môi trường:

```dotenv
CHAIN_ID=11155111
BLOCKCHAIN_RPC_URL=https://sepolia.infura.io/v3/<PROJECT_ID>
HOP_DONG_CUA_HANG=0x...
HOP_DONG_VAT_PHAM=0x...
HOP_DONG_SBT=0x...
SBT_ENABLED=true
SBT_CHAIN_ID=11155111
SBT_AUTHORIZED_SIGNER=0x...
```

Private key chỉ được đặt trong `.env` local hoặc secret của Render/GitHub. Không commit private key, seed phrase, token API hoặc thông tin đăng nhập vào Git.

## Faucet Sepolia

Backend có thể cấp ETH test cho ví người chơi thiếu phí gas. Luồng tổng quát:

1. Backend kiểm tra số dư ví trên Sepolia.
2. Nếu thiếu ETH, backend gửi giao dịch faucet từ ví cấp phát.
3. Backend trả trạng thái giao dịch để frontend tiếp tục theo dõi.
4. Frontend kiểm tra lại số dư trước khi yêu cầu người chơi ký giao dịch.

Faucet chỉ dùng cho Sepolia/testnet. Cần cấu hình đúng RPC, địa chỉ ví faucet và private key tương ứng trong môi trường Render. Private key của faucet không phải địa chỉ ví; địa chỉ là public address, còn private key là chuỗi bí mật của chính ví đó.

## Huy hiệu SBT

Luồng SBT sử dụng contract thành tích riêng và chữ ký EIP-712:

- `HOP_DONG_SBT`: địa chỉ contract ThanhTuuSBT trên đúng mạng.
- `SBT_AUTHORIZED_SIGNER`: địa chỉ public tương ứng với private key ký backend.
- `SBT_SIGNER_PRIVATE_KEY`: private key của signer được contract ủy quyền.
- `SBT_VOUCHER_TTL_SECONDS`: thời hạn voucher, ví dụ `900` giây.

Không dùng private key ví người chơi để làm signer backend nếu không thật sự cần thiết. Sau khi thay đổi biến môi trường trên Render, cần lưu/redeploy service rồi kiểm tra log và transaction trên Sepolia explorer.

## Mã QR quà tặng

Tạo mã QR từ thư mục gốc:

```bash
python gold_rush_ai/scripts/tao_ma_qr_qua_tang.py \
  --type gold \
  --amount 100 \
  --max-uses 1 \
  --per-wallet-limit 1 \
  --name "Quà quay thưởng"
```

Mã QR chỉ là hình ảnh chứa code. Backend mới là nơi xác thực và cấp thưởng. Dữ liệu mã được lưu trong:

```text
gold_rush_ai/data/qua_tang/codes.json
```

Khi tạo mã mới:

1. Kiểm tra code đã được ghi vào `codes.json`.
2. Giữ `maxUses` và `perWalletLimit` phù hợp với thể lệ.
3. Push `codes.json` lên Git để Render deploy backend đọc dữ liệu mới.
4. Lưu ảnh PNG ở nơi phát hành QR; ảnh không bắt buộc phải nằm trong repository để backend claim hoạt động.

> QR code là dữ liệu có thể đổi lấy phần thưởng. Không công khai mã chưa phát hành và nên thu hồi/đổi mã nếu bị lộ.

## Kiểm thử

### Smart contracts

```bash
cd gold_rush_chain
npx hardhat compile
npx hardhat test
```

### Backend

```bash
cd gold_rush_ai
source .venv/bin/activate
pytest -v
```

Một số test tích hợp cần database, biến môi trường hoặc service tương ứng. Khi kiểm tra nhanh theo pipeline CI, dùng đúng nhóm test được khai báo trong `.github/workflows/ci.yml`.

### Flutter

```bash
cd gold_rush
flutter analyze --no-fatal-infos
flutter test
```

Một lần chạy toàn bộ bộ test trước đợt sửa Android ghi nhận **583 test đạt**
và **42 test bỏ qua**. Đợt sửa Android ghi nhận **187 test đạt** trong nhóm
xác thực ví native và blockchain. Có thể chạy lại nhóm này từ `gold_rush/`
bằng PowerShell.

```powershell
$blockchainTests = Get-ChildItem test/blockchain -Recurse -Filter '*_test.dart' |
  Where-Object { $_.Name -notlike '*_web_test.dart' } |
  ForEach-Object FullName
flutter test test/auth/metamask_siwe_native_test.dart @blockchainTests
flutter test test/man_hinh/trung_tam_qua_tang_test.dart test/chien_dau/ban_sat_mep_test.dart test/chien_dau/ban_ap_sat_test.dart
```

## Kiểm tra nhanh bản Web

Sau khi deploy, kiểm tra lần lượt các luồng chính:

1. Đăng nhập bằng MetaMask và xác nhận đúng mạng Sepolia.
2. Mở Sảnh chờ, Bản đồ thế giới và chọn một màn đã mở khóa.
3. Mở Cửa hàng, kiểm tra danh mục và vật phẩm hiển thị.
4. Mở Kho đồ, kiểm tra số lượng vật phẩm và trạng thái đồng bộ.
5. Mở Trung tâm quà tặng, kiểm tra nút mở QR scanner và quyền camera.
6. Nếu test giao dịch, dùng ví test có Sepolia ETH và chỉ kiểm tra trên testnet.

Không thực hiện mua hàng hoặc claim QR trong smoke test nếu không muốn thay đổi
dữ liệu tài khoản đang dùng.

## CI/CD

Các workflow nằm trong `.github/workflows/`:

| Workflow | Khi chạy | Kết quả |
|---|---|---|
| `ci.yml` | Push/PR vào `main`, `dev` | Compile/test contract, test backend, analyze/test Flutter |
| `deploy-web.yml` | Thay đổi `gold_rush/**` trên `main` | Build Flutter Web và deploy Firebase Hosting nếu có `FIREBASE_TOKEN` |
| `build-apk.yml` | Thay đổi `gold_rush/**` hoặc tag `v*` | Build APK, upload artifact; tag `v*` tạo GitHub Release |

Workflow APK hiện chỉ truyền `GOLD_RUSH_API`. Để gửi bản có luồng kết nối
MetaMask, dùng lệnh đóng gói thủ công với đầy đủ cấu hình Android bên dưới.

Backend Render được cấu hình Auto-Deploy theo branch `main`. Vì vậy thay đổi backend hoặc dữ liệu QR cần push lên `main` để Render nhận commit và tạo deploy mới. Có thể kiểm tra trạng thái tại mục **Deploys** của service `gold-rush-api`.

Để tạo bản APK phát hành bằng tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Các secret cần được đặt trong GitHub/Render, không đặt trong workflow hoặc README:

- `FIREBASE_TOKEN` cho Firebase Hosting.
- RPC URL, contract address và các khóa ký cần thiết cho Render.

## Đóng gói APK thủ công

Máy build cần Flutter, Android SDK Platform 37, Build Tools và Platform Tools.
Bản APK test trên Windows được build với Flutter 3.50.1, JDK 21 chạy Gradle,
NDK 28.2.13676358 và CMake 3.22.1. Mã ứng dụng vẫn nhắm Java 17. Dùng
`flutter doctor -v` để kiểm tra JDK và SDK Flutter đang dùng.

Từ thư mục gốc, lưu cấu hình dưới đây vào
`build/gold-rush-android-defines.json` và thay `<project-id>` bằng Project ID
của Gold Rush trên Reown. Thư mục `build/` được Git bỏ qua.

```json
{
  "GOLD_RUSH_API": "https://gold-rush-api.onrender.com",
  "REOWN_PROJECT_ID": "<project-id>",
  "GOLD_RUSH_DAPP_URL": "https://gold-rush-web.web.app",
  "GOLD_RUSH_NATIVE_ORIGIN": "https://gold-rush-web.web.app",
  "GOLD_RUSH_NATIVE_REDIRECT": "goldrush://",
  "GOLD_RUSH_APP_LINK": "https://gold-rush-web.web.app/wc",
  "GOLD_RUSH_SEPOLIA_RPC_URL": "https://ethereum-sepolia-rpc.publicnode.com"
}
```

Backend phải cho phép giá trị `GOLD_RUSH_NATIVE_ORIGIN` và trả cấu hình hợp
đồng trên Sepolia. Android dùng `goldrush://` để nhận lượt quay lại từ ví.
Giữ private key và cụm từ khôi phục ngoài cấu hình build.

Chạy từ thư mục gốc bằng PowerShell. Có thể truyền thêm
`--build-number=N` với số lớn hơn bản đã gửi để tester cài cập nhật.

```powershell
$defines = (Resolve-Path .\build\gold-rush-android-defines.json).Path
Set-Location .\gold_rush
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 "--dart-define-from-file=$defines"
```

APK chứa ba kiến trúc `armeabi-v7a`, `arm64-v8a` và `x86_64`. Từ thư
mục gốc, file đầu ra nằm ở đường dẫn sau.

```text
gold_rush/build/app/outputs/flutter-apk/app-release.apk
```

Nếu đã biết kiến trúc thiết bị, có thể thêm `--split-per-abi` vào lệnh
build để tạo APK nhỏ hơn cho từng kiến trúc.

APK kiểm thử đã xuất trên máy build ở `build/GoldRush-1.3.0-build5-Android.apk`
(`1.3.0+5`, Android 7.0 trở lên). Bản này có các sửa lỗi ví và đồng bộ
Android trước đợt chỉnh giao diện. Bố cục trang Quà tặng và nút **Bắn** ở
mã nguồn cần được build lại để có trong APK gửi tiếp theo.

Có thể gửi APK qua Drive hoặc USB. Tester mở APK trên điện thoại và cấp quyền
cài ứng dụng từ nguồn đã mở tệp khi Android hỏi. Với ADB, chạy từ thư mục gốc.

```powershell
adb devices
adb install -r .\gold_rush\build\app\outputs\flutter-apk\app-release.apk
```

APK nội bộ dùng khóa debug. Cài đè cần cùng khóa ký và số build phù hợp.
Khi phát hành qua Google Play, cấu hình upload key riêng trong
`gold_rush/android/app/build.gradle.kts`.

## Kiểm tra nhanh bản Android

1. Mở khóa MetaMask Mobile, chọn Sepolia, mở Gold Rush và bấm **Kết nối MetaMask**.
   Duyệt kết nối rồi ký thông điệp đăng nhập. Kiểm tra Gold Rush mở lại sau khi duyệt.
2. Mở **Cửa hàng** và **Kho đồ**. Kiểm tra tải danh mục, số vàng, vật phẩm, trang
   bị đang dùng và nút làm mới. Kiểm tra `/api/health` và `/api/vang/cau-hinh` nếu
   cả hai trang đều chờ dữ liệu.
3. Dùng ví test có Sepolia ETH để thử vào màn, mua vật phẩm, mua nhân vật,
   mở rương, nhận vật phẩm hoặc nhận huy hiệu theo điều kiện của tài khoản.
   Đọc thông điệp ký và kiểm tra biên lai cùng dữ liệu sau khi quay lại game.
4. Với APK build từ mã nguồn đã chỉnh giao diện, mở **Quà tặng** ở chế độ
   ngang, kiểm tra nút quét QR hiện trong khung hình và cấp quyền camera khi
   được hỏi. Vào màn chơi để kiểm tra vị trí và vùng chạm của nút **Bắn**.

API demo trả HTTP 200 ở `/api/health`, `/api/vang/cau-hinh` và `/api/man`.
Cấu hình hợp đồng trả chain ID `11155111`. Các API hồ sơ, kho đồ và huy
hiệu trả HTTP 401 khi Origin hợp lệ và chưa có phiên. Luồng challenge và
verify thử nghiệm nhận `registration_required` với ví mới. Trên Sepolia đã
kiểm tra mã triển khai và cấu hình của
`CuaHangGoldRush`, `VatPhamGoldRush`, `CharacterRegistry` và
`ThanhTuuSBT`. Bước duyệt MetaMask và xác nhận giao dịch đầu cuối trên
điện thoại Android thật vẫn cần tester thực hiện.

## Quy trình đóng góp

```bash
git status
git diff --check
git add <file-can-thay-doi>
git commit -m "Mô tả thay đổi bằng tiếng Việt"
git push origin main
```

Trước khi push nên kiểm tra:

- Không có `.env`, private key hoặc seed phrase trong staged files.
- `git diff --cached --check` không báo lỗi khoảng trắng.
- Test phù hợp với phần đã sửa đã chạy.
- Sau push, kiểm tra GitHub Actions, Render Deploys và Firebase Deploy nếu có thay đổi frontend.

## Checklist hoàn thiện đồ án

- [x] Có gameplay 2D và bản đồ nhiều màn.
- [x] Có đăng nhập ví và tích hợp Web3.
- [x] Có backend FastAPI và lưu dữ liệu người chơi.
- [x] Có smart contract cửa hàng/NFT và tài liệu tích hợp.
- [x] Có luồng huy hiệu SBT và voucher chữ ký.
- [x] Có faucet Sepolia cho môi trường test.
- [x] Có mã QR quà tặng và giới hạn lượt nhận.
- [x] Có test contract, backend và Flutter trong CI.
- [x] Có workflow deploy web và build APK.
- [ ] Chốt bản APK cuối, cài thử trên thiết bị thật và lưu ảnh/video minh chứng.
- [ ] Kiểm tra toàn bộ biến môi trường production/demo trước buổi bảo vệ.

## Giới hạn và lưu ý hiện tại

- Sepolia là testnet; thời gian xác nhận giao dịch phụ thuộc RPC và tốc độ mine.
- Render Free có thể sleep khi không có traffic, khiến request đầu tiên chậm.
- Nếu backend dùng SQLite trên filesystem tạm thời, dữ liệu có thể mất khi service restart/redeploy; production nên dùng PostgreSQL hoặc persistent storage.
- Frontend chỉ tự deploy Firebase khi commit có thay đổi trong phạm vi workflow và secret Firebase đã được cấu hình.
- Thay đổi chỉ ở backend/QR không kích hoạt workflow build web/APK, nhưng vẫn kích hoạt Render nếu Auto-Deploy của service đang bật.

## Giấy phép

Đây là đồ án phục vụ học tập và kiểm thử trên testnet. Khi tái sử dụng, cần kiểm tra lại bản quyền asset, thư viện và cấu hình blockchain tương ứng.


