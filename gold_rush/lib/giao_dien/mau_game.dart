import 'package:flutter/material.dart';

import '../cau_hinh.dart';

/// Bảng màu dùng chung cho World Map và Kho đồ.
class MauGame {
  MauGame._();

  // Kế thừa màu của Gold Rush hiện tại.
  static const Color chinh = CauHinh.mauChinh;
  static const Color nen = CauHinh.mauNen;
  static const Color nenPhu = CauHinh.mauNenMo;
  static const Color chu = CauHinh.mauChu;

  // Màu bổ trợ dùng thống nhất trong các giao diện mới.
  static const Color chuPhu = Color(0xFFC9D2DB);
  static const Color vien = Color(0x66FFFFFF);
  static const Color chuTrenVang = Color(0xFF241A05);
}