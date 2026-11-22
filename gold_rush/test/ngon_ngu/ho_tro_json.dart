import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';

/// Tests mounting widgets directly use the same resource bootstrap as main().
Future<void> chuanBiNgonNguChoKiemThu() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await NgonNgu.chung.chuanBi();
}
