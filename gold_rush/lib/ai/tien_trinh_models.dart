import 'package:flutter/foundation.dart';

/// Chi tiết tiến trình của một màn chơi cụ thể (1–6).
@immutable
class ChiTietManChoi {
  final int stageId;
  final String name;
  final String status; // 'completed', 'unlocked', 'locked'
  final String? verificationSource;
  final String? completedAt;

  const ChiTietManChoi({
    required this.stageId,
    required this.name,
    required this.status,
    this.verificationSource,
    this.completedAt,
  });

  bool get isCompleted => status == 'completed';
  bool get isUnlocked => status == 'unlocked' || isCompleted;
  bool get isLocked => status == 'locked';

  factory ChiTietManChoi.tuJson(Map<String, dynamic> json) {
    final sId = json['stage_id'];
    final name = json['name'];
    final status = json['status'];
    if (sId is! int || sId < 1 || sId > 6) {
      throw const FormatException('stage_id phải là số nguyên từ 1 đến 6');
    }
    if (name is! String || name.isEmpty) {
      throw const FormatException('name phải là chuỗi không rỗng');
    }
    if (status is! String ||
        (status != 'completed' && status != 'unlocked' && status != 'locked')) {
      throw const FormatException('status phải là completed, unlocked hoặc locked');
    }
    return ChiTietManChoi(
      stageId: sId,
      name: name,
      status: status,
      verificationSource: json['verification_source'] as String?,
      completedAt: json['completed_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'stage_id': stageId,
    'name': name,
    'status': status,
    if (verificationSource != null) 'verification_source': verificationSource,
    if (completedAt != null) 'completed_at': completedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChiTietManChoi &&
          runtimeType == other.runtimeType &&
          stageId == other.stageId &&
          name == other.name &&
          status == other.status &&
          verificationSource == other.verificationSource &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(stageId, name, status, verificationSource, completedAt);

  @override
  String toString() => 'ChiTietManChoi(stageId: $stageId, name: $name, status: $status)';
}

/// Bản ghi chi tiết xác minh của một màn chơi đã hoàn thành.
@immutable
class BanGhiTienTrinh {
  final int? id;
  final String ownerUserId;
  final String verifiedWalletAddress;
  final int stageId;
  final String completionStatus;
  final String verificationSource;
  final Map<String, dynamic> completionEvidence;
  final String replayKey;
  final String completedAt;
  final String? createdAt;

  const BanGhiTienTrinh({
    this.id,
    required this.ownerUserId,
    required this.verifiedWalletAddress,
    required this.stageId,
    required this.completionStatus,
    required this.verificationSource,
    required this.completionEvidence,
    required this.replayKey,
    required this.completedAt,
    this.createdAt,
  });

  factory BanGhiTienTrinh.tuJson(Map<String, dynamic> json) {
    final sId = json['stage_id'];
    final owner = json['owner_user_id'];
    final wallet = json['verified_wallet_address'];
    final status = json['completion_status'];
    final source = json['verification_source'];
    final replay = json['replay_key'];
    final completedAt = json['completed_at'];

    if (sId is! int || sId < 1 || sId > 6) {
      throw const FormatException('stage_id phải là số nguyên từ 1 đến 6');
    }
    if (owner is! String || owner.isEmpty) {
      throw const FormatException('owner_user_id không được rỗng');
    }
    if (wallet is! String || wallet.isEmpty) {
      throw const FormatException('verified_wallet_address không được rỗng');
    }
    if (status is! String || status != 'completed') {
      throw const FormatException('completion_status phải là completed');
    }
    if (source is! String || source.isEmpty) {
      throw const FormatException('verification_source không được rỗng');
    }
    if (replay is! String || replay.isEmpty) {
      throw const FormatException('replay_key không được rỗng');
    }
    if (completedAt is! String || completedAt.isEmpty) {
      throw const FormatException('completed_at không được rỗng');
    }

    final rawEvidence = json['completion_evidence'];
    final Map<String, dynamic> evidence =
        rawEvidence is Map<String, dynamic> ? rawEvidence : const {};

    return BanGhiTienTrinh(
      id: json['id'] as int?,
      ownerUserId: owner,
      verifiedWalletAddress: wallet,
      stageId: sId,
      completionStatus: status,
      verificationSource: source,
      completionEvidence: evidence,
      replayKey: replay,
      completedAt: completedAt,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'owner_user_id': ownerUserId,
    'verified_wallet_address': verifiedWalletAddress,
    'stage_id': stageId,
    'completion_status': completionStatus,
    'verification_source': verificationSource,
    'completion_evidence': completionEvidence,
    'replay_key': replayKey,
    'completed_at': completedAt,
    if (createdAt != null) 'created_at': createdAt,
  };
}

/// Phản hồi tổng quan tiến trình từ GET /api/ai/tien-trinh.
@immutable
class PhanHoiTienTrinh {
  final String ownerUserId;
  final String verifiedWalletAddress;
  final List<int> completedStageIds;
  final List<int> allowedStageIds;
  final List<ChiTietManChoi> stages;
  final int totalCompleted;
  final bool isCharacterUnlocked;

  const PhanHoiTienTrinh({
    required this.ownerUserId,
    required this.verifiedWalletAddress,
    required this.completedStageIds,
    required this.allowedStageIds,
    required this.stages,
    required this.totalCompleted,
    required this.isCharacterUnlocked,
  });

  /// Tạo đối tượng rỗng mặc định (khi chưa có dữ liệu hoặc tài khoản mới).
  factory PhanHoiTienTrinh.rong({
    String ownerUserId = '',
    String verifiedWalletAddress = '',
  }) {
    final stages = List.generate(
      6,
      (i) => ChiTietManChoi(
        stageId: i + 1,
        name: _tenMan(i + 1),
        status: i == 0 ? 'unlocked' : 'unlocked', // Tất cả màn đều unlock theo logic backend
      ),
    );
    return PhanHoiTienTrinh(
      ownerUserId: ownerUserId,
      verifiedWalletAddress: verifiedWalletAddress,
      completedStageIds: const [],
      allowedStageIds: const [1, 2, 3, 4, 5, 6],
      stages: stages,
      totalCompleted: 0,
      isCharacterUnlocked: false,
    );
  }

  static String _tenMan(int id) {
    const names = {
      1: 'Đồng cỏ',
      2: 'Rừng thưa',
      3: 'Hang đá',
      4: 'Rừng rậm',
      5: 'Thung lũng xương',
      6: 'Mỏ vàng',
    };
    return names[id] ?? 'Màn $id';
  }

  factory PhanHoiTienTrinh.tuJson(Map<String, dynamic> json) {
    final owner = json['owner_user_id'];
    final wallet = json['verified_wallet_address'];
    final completed = json['completed_stage_ids'];
    final allowed = json['allowed_stage_ids'];
    final stagesRaw = json['stages'];
    final total = json['total_completed'];
    final unlocked = json['is_character_unlocked'];

    if (owner is! String || owner.isEmpty) {
      throw const FormatException('owner_user_id không được rỗng');
    }
    if (wallet is! String || wallet.isEmpty) {
      throw const FormatException('verified_wallet_address không được rỗng');
    }
    if (completed is! List) {
      throw const FormatException('completed_stage_ids phải là danh sách');
    }
    if (allowed is! List) {
      throw const FormatException('allowed_stage_ids phải là danh sách');
    }
    if (stagesRaw is! List) {
      throw const FormatException('stages phải là danh sách');
    }
    if (total is! int) {
      throw const FormatException('total_completed phải là số nguyên');
    }
    if (unlocked is! bool) {
      throw const FormatException('is_character_unlocked phải là boolean');
    }

    final completedIds = completed.cast<int>();
    final allowedIds = allowed.cast<int>();
    final stages = stagesRaw
        .map((s) => ChiTietManChoi.tuJson(s as Map<String, dynamic>))
        .toList();

    return PhanHoiTienTrinh(
      ownerUserId: owner,
      verifiedWalletAddress: wallet,
      completedStageIds: List.unmodifiable(completedIds),
      allowedStageIds: List.unmodifiable(allowedIds),
      stages: List.unmodifiable(stages),
      totalCompleted: total,
      isCharacterUnlocked: unlocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'owner_user_id': ownerUserId,
    'verified_wallet_address': verifiedWalletAddress,
    'completed_stage_ids': completedStageIds,
    'allowed_stage_ids': allowedStageIds,
    'stages': stages.map((s) => s.toJson()).toList(),
    'total_completed': totalCompleted,
    'is_character_unlocked': isCharacterUnlocked,
  };

  @override
  String toString() =>
      'PhanHoiTienTrinh(totalCompleted: $totalCompleted/6, isCharacterUnlocked: $isCharacterUnlocked)';
}
