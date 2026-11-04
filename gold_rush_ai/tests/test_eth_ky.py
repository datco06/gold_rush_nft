"""Kiểm chứng mật mã thuần Python bằng véc-tơ kiểm thử CÔNG KHAI — sai một bit là đỏ."""
import unittest

from core.eth_ky import (MIEN, bam_cau_truc, checksum, dia_chi_tu_khoa, keccak256, ky,
                         phuc_hoi, N)


class TestKeccak(unittest.TestCase):
    def test_vec_to_chuan(self):
        self.assertEqual(keccak256(b"").hex(),
                         "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        self.assertEqual(keccak256(b"abc").hex(),
                         "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")

    def test_khac_sha3_cua_hashlib(self):
        import hashlib
        self.assertNotEqual(keccak256(b"").hex(), hashlib.sha3_256(b"").hexdigest())

    def test_nhieu_khoi(self):
        # 200 byte > 136 byte/khối: kiểm tra phần nối khối
        self.assertEqual(len(keccak256(b"a" * 200)), 32)
        self.assertNotEqual(keccak256(b"a" * 136), keccak256(b"a" * 137))


class TestDiaChi(unittest.TestCase):
    def test_tai_khoan_hardhat(self):
        # Ba tài khoản thử đầu tiên mà `npx hardhat node` in ra
        self.assertEqual(dia_chi_tu_khoa(bytes.fromhex(
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80")),
            "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
        self.assertEqual(dia_chi_tu_khoa(bytes.fromhex(
            "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d")),
            "0x70997970C51812dc3A010C7d01b50e0d17dc79C8")

    def test_checksum_eip55(self):
        self.assertEqual(checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"),
                         "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")

    def test_dia_chi_hop_dong_dau_tien(self):
        # Hợp đồng đầu tiên tài khoản #0 triển khai (nonce 0) = keccak(rlp([địa chỉ, 0]))[12:]
        a = bytes.fromhex("f39Fd6e51aad88F6F4ce6aB8827279cffFb92266")
        self.assertEqual(checksum(keccak256(bytes([0xd6, 0x94]) + a + b"\x80")[-20:].hex()),
                         "0x5FbDB2315678afecb367f032d93F642f64180aa3")


class TestEip712(unittest.TestCase):
    def test_vi_du_mail_trong_dac_ta(self):
        """Ví dụ 'Ether Mail' của đặc tả EIP-712: bản băm VÀ chữ ký phải đúng từng byte."""
        mien = {"name": "Ether Mail", "version": "1", "chainId": 1,
                "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"}
        nguoi = [("name", "string"), ("wallet", "address")]
        p = lambda ten, vi: bam_cau_truc("Person", nguoi, {"name": ten, "wallet": vi})  # noqa: E731
        thu = keccak256(keccak256(b"Mail(Person from,Person to,string contents)Person(string name,address wallet)")
                        + p("Cow", "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826")
                        + p("Bob", "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB")
                        + keccak256(b"Hello, Bob!"))
        bam = keccak256(b"\x19\x01" + bam_cau_truc("EIP712Domain", MIEN, mien) + thu)
        self.assertEqual(bam.hex(), "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2")
        ck = ky(bam, keccak256(b"cow"))
        self.assertEqual(ck[64], 28)
        self.assertEqual(ck[:32].hex(), "4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d")
        self.assertEqual(ck[32:64].hex(), "07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b91562")

    def test_ky_roi_phuc_hoi_va_s_thap(self):
        khoa = keccak256(b"trong tai")
        for i in range(20):
            bam = keccak256(bytes([i]))
            ck = ky(bam, khoa)
            self.assertEqual(phuc_hoi(bam, ck), dia_chi_tu_khoa(khoa))
            self.assertLessEqual(int.from_bytes(ck[32:64], "big"), N // 2)   # OpenZeppelin từ chối s cao
            self.assertIn(ck[64], (27, 28))


if __name__ == "__main__":
    unittest.main()
