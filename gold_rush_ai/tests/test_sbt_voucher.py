from core.sbt_voucher import DichVuVoucherSBT


PRIVATE_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
SIGNER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
PLAYER = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CONTRACT = "0xcccccccccccccccccccccccccccccccccccccccc"


def test_sbt_voucher_ky_dung_domain_va_player():
    service = DichVuVoucherSBT(
        private_key=PRIVATE_KEY,
        contract_address=CONTRACT,
        chain_id=31337,
        authorized_signer=SIGNER,
        ttl_seconds=900,
    )
    result = service.tao_va_ky(player=PLAYER, achievement_id=2, now=1_000)

    assert result["primaryType"] == "PhieuSBT"
    assert result["domain"]["name"] == "GoldRushSBT"
    assert result["domain"]["version"] == "1"
    assert result["domain"]["chainId"] == 31337
    assert result["domain"]["verifyingContract"].lower() == CONTRACT.lower()
    assert result["phieu"]["player"].lower() == PLAYER.lower()
    assert result["phieu"]["achievementId"] == 2
    assert result["phieu"]["deadline"] == "1900"
    assert len(result["chuKy"]) == 132
    assert result["signerAddress"].lower() == SIGNER.lower()


def test_sbt_voucher_tu_choi_achievement_sai():
    service = DichVuVoucherSBT(
        private_key=PRIVATE_KEY,
        contract_address=CONTRACT,
        chain_id=31337,
    )
    try:
        service.tao_va_ky(player=PLAYER, achievement_id=6, now=1_000)
    except ValueError as error:
        assert "từ 1 đến 5" in str(error)
    else:
        raise AssertionError("achievement_id ngoài phạm vi phải bị từ chối")
