class HoSoCapDo {
  static const int capToiDa = 10;

  int level = 1;
  int currentExp = 0;
  int skillPoints = 0;

  static int expCanChoCap(int cap) => 40 + (cap - 1) * 20;

  int get expToNextLevel => expCanChoCap(level);
  bool get daToiDa => level >= capToiDa;

  /// Thưởng sát thương cộng thêm theo cấp.
  int get thuongSatThuong => (level - 1) * 2;

  /// Cộng EXP. Trả về số cấp vừa lên.
  int congExp(int exp) {
    if (exp <= 0 || daToiDa) return 0;
    currentExp += exp;
    var len = 0;
    while (!daToiDa && currentExp >= expToNextLevel) {
      currentExp -= expToNextLevel;
      level++;
      skillPoints++;
      len++;
    }
    if (daToiDa) currentExp = 0;
    return len;
  }
}