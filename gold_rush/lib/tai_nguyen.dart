import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import 'blockchain/nhan_vat.dart';
import 'cau_hinh.dart';

/// Nạp và giữ toàn bộ hình ảnh của game ở MỘT chỗ.
///
/// Vì sao không để mỗi component tự nạp ảnh của mình:
///
///  * Nạp ảnh là thao tác bất đồng bộ và tốn thời gian. Nạp một lần lúc khởi
///    động thì lúc chơi không bao giờ bị khựng.
///  * Mười con quái dùng chung một `SpriteAnimation` thay vì mười bản sao.
///  * Component không cần biết gì về `Flame.images` -> dễ kiểm thử hơn.
class TaiNguyen {
  late final Map<HuongDi, SpriteAnimation> george;

  /// Hoạt ảnh của George theo tên tệp sprite — George gốc + các nhân vật mua trong cửa
  /// hàng (lib/blockchain/nhan_vat.dart). Thiếu tệp nào thì bỏ qua tệp đó.
  final Map<String, Map<HuongDi, SpriteAnimation>> georgeTheoTep = {};
  final Map<String, ui.Image> anhNhanVatTheoKhoa = {};
  final Map<String, Map<HuongDi, SpriteAnimation>> trangBiTheoTep = {};
  late final Map<HuongDi, SpriteAnimation> zombie;
  late final Map<HuongDi, SpriteAnimation> skeleton;
  late final Map<HuongDi, SpriteAnimation> quaiThuong;
  late final Map<HuongDi, SpriteAnimation> quaiGiap;
  late final Map<HuongDi, SpriteAnimation> quaiKhongLo;
  late final SpriteAnimation dongXu;
  late final Sprite joystickNen;
  late final Sprite joystickNum;

  /// Gọi đúng một lần trong `onLoad` của game.
  Future<void> nap() async {
    final anhGeorge = await Flame.images.load('george.png');
    final anhZombie = await Flame.images.load('zombie.png');
    final anhSkeleton = await Flame.images.load('skeleton.png');
    final anhQuaiThuong = await Flame.images.load('quai_thuong.png');
    final anhQuaiGiap = await Flame.images.load('quai_giap.png');
    final anhQuaiKhongLo = await Flame.images.load('quai_khong_lo.png');
    final anhDongXu = await Flame.images.load('dong_xu.png');

    george = _bonHuong(anhGeorge, 0.12);
    georgeTheoTep[georgeGoc.tepAnh] = george;
    for (final nv in bangNhanVat) {
      try {
        georgeTheoTep[nv.tepAnh] = _bonHuong(
          await Flame.images.load(nv.tepAnh),
          0.12,
        );
      } catch (_) {
        // Chưa chạy cong-cu/sinh_nhan_vat.py: nhân vật đó dùng hình George gốc.
      }
    }
    zombie = _bonHuong(anhZombie, 0.18);
    skeleton = _bonHuong(anhSkeleton, 0.14);
    quaiThuong = _bonHuong(anhQuaiThuong, 0.18, frameSize: 64);
    quaiGiap = _bonHuong(anhQuaiGiap, 0.16, frameSize: 64);
    quaiKhongLo = _bonHuong(anhQuaiKhongLo, 0.2, frameSize: 64);

    // Nạp sprite sheet trang bị theo đúng 4 hướng x 4 frame.
    const trangBiFiles = [
      'sung_cap_1_sprite_4x4.png',
      'sung_cap_2_sprite_4x4.png',
      'sung_cap_3_sprite_4x4.png',
      'sung_manh_1_sprite_4x4.png',
      'sung_manh_2_sprite_4x4.png',
      'sung_manh_3_sprite_4x4.png',
      'sung_hiem_xuyen_pha.png',
      'sung_hiem_bao_tinh_the.png',
      'sung_hiem_hac_long.png',
      'giap_thuong_cap_1.png',
      'giap_thuong_cap_2.png',
      'giap_thuong_cap_3.png',
      'giap_manh_cap_1.png',
      'giap_manh_cap_2.png',
      'giap_manh_cap_3.png',
      'giap_hiem_hac_long.png',
      'giap_hiem_tinh_the.png',
      'giap_hiem_hoang_kim.png',
      'giay_thuong_cap_1.png',
      'giay_thuong_cap_2.png',
      'giay_thuong_cap_3.png',
      'giay_manh_cap_1.png',
      'giay_manh_cap_2.png',
      'giay_manh_cap_3.png',
      'giay_hiem_hac_long.png',
      'giay_hiem_tinh_the.png',
      'giay_hiem_phuong_hoang.png',
    ];
    for (final tep in trangBiFiles) {
      final anh = await Flame.images.load('trang_bi/$tep');
      trangBiTheoTep[tep] = _bonHuong(anh, 0.12, frameSize: 64);
    }

    dongXu = SpriteAnimation.fromFrameData(
      anhDongXu,
      SpriteAnimationData.sequenced(
        amount: 8,
        amountPerRow: 8,
        stepTime: 0.09,
        textureSize: Vector2.all(CauHinh.kichThuocO),
      ),
    );

    joystickNen = Sprite(await Flame.images.load('joystick_nen.png'));
    joystickNum = Sprite(await Flame.images.load('joystick_num.png'));
  }

  /// Nạp sprite-sheet AI 4x4 từ bytes backend. Mỗi ô 16x16, giống sprite
  /// George nên gameplay dùng cùng component/điều khiển hiện có.
  Future<void> napNhanVatAi(String khoa, Uint8List png) async {
    final codec = await ui
        .instantiateImageCodec(Uint8List.fromList(png))
        .timeout(const Duration(seconds: 8));
    try {
      if (codec.frameCount != 1) {
        throw const FormatException('Sprite nhân vật AI phải là ảnh tĩnh');
      }
      final frame = await codec.getNextFrame().timeout(
        const Duration(seconds: 8),
      );
      final image = frame.image;
      if (image.width != 64 || image.height != 64) {
        image.dispose();
        throw const FormatException(
          'Sprite nhân vật AI phải có kích thước 64x64',
        );
      }
      anhNhanVatTheoKhoa[khoa] = image;
      georgeTheoTep[khoa] = _bonHuong(image, 0.12, frameSize: 16);
    } finally {
      codec.dispose();
    }
  }

  ui.Image? anhNhanVat(String khoa) => anhNhanVatTheoKhoa[khoa];

  /// Khởi tạo hoạt ảnh giả từ một `ui.Image` trong bộ nhớ để chạy kiểm thử nhanh.
  void napTuAnhGia(ui.Image anh) {
    george = _bonHuong(anh, 0.12);
    georgeTheoTep[georgeGoc.tepAnh] = george;
    zombie = _bonHuong(anh, 0.18);
    skeleton = _bonHuong(anh, 0.14);
    quaiThuong = _bonHuong(anh, 0.18);
    quaiGiap = _bonHuong(anh, 0.16);
    quaiKhongLo = _bonHuong(anh, 0.2);
    dongXu = SpriteAnimation.fromFrameData(
      anh,
      SpriteAnimationData.sequenced(
        amount: 1,
        amountPerRow: 1,
        stepTime: 0.09,
        textureSize: Vector2.all(CauHinh.kichThuocO),
      ),
    );
    joystickNen = Sprite(anh);
    joystickNum = Sprite(anh);
  }

  /// Cắt một sprite sheet 4 hàng × 4 cột thành bốn hoạt ảnh theo hướng.
  ///
  /// `texturePosition` là góc trên-trái của hàng cần cắt. Hàng thứ `i` bắt đầu
  /// ở toạ độ y = i × 16. Đây là chỗ hay nhầm nhất khi làm việc với sprite
  /// sheet: nhầm hàng thì nhân vật đi xuống mà hoạt ảnh lại quay lưng.
  Map<HuongDi, SpriteAnimation> _bonHuong(
    ui.Image anh,
    double buocThoiGian, {
    double frameSize = CauHinh.kichThuocO,
  }) {
    SpriteAnimation hang(int i) => SpriteAnimation.fromFrameData(
      anh,
      SpriteAnimationData.sequenced(
        amount: 4,
        amountPerRow: 4,
        stepTime: buocThoiGian,
        textureSize: Vector2.all(frameSize),
        texturePosition: Vector2(0, i * frameSize),
      ),
    );

    return {
      HuongDi.xuong: hang(0),
      HuongDi.trai: hang(1),
      HuongDi.phai: hang(2),
      HuongDi.len: hang(3),
    };
  }
}
