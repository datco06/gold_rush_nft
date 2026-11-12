// Sinh lại fixture bằng ABI thật và viem đã cài trong gold_rush_chain.
// Chạy tại gold_rush: node test/blockchain/vat_pham/sinh_mau_viem.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../../../gold_rush_chain/package.json', import.meta.url));
const { encodeFunctionData, encodeFunctionResult, toFunctionSelector, keccak256, toHex } = require('viem');
const { abi } = JSON.parse(readFileSync(new URL('../../../../gold_rush_chain/artifacts/contracts/VatPhamGoldRush.sol/VatPhamGoldRush.json', import.meta.url)));
const contract = `0x${'a'.repeat(40)}`;
const player = `0x${'b'.repeat(40)}`;
const recipient = `0x${'c'.repeat(40)}`;
const chainId = 31337;
const voucher = { player, tokenId: (1n << 200n) + 1n, amount: 3n, nonce: `0x${'d'.repeat(64)}`, deadline: (1n << 100n) + 123n };
const signature = `0x${'11'.repeat(64)}1b`; // Chỉ dùng kiểm tra ABI, không phải phiếu hợp lệ.
const typehash = keccak256(toHex('PhieuVatPham(address player,uint256 tokenId,uint256 amount,bytes32 nonce,uint256 deadline)'));
const calls = {};
const results = {};
function sample(key, functionName, args, result) {
  calls[key] = encodeFunctionData({ abi, functionName, args });
  if (result !== undefined) results[key] = encodeFunctionResult({ abi, functionName, result });
}
sample('typehash', 'PHIEU_VAT_PHAM_TYPEHASH', [], typehash);
sample('domain', 'eip712Domain', [], ['0x0f', 'GoldRushEquipment', '1', BigInt(chainId), contract, toHex(0n, { size: 32 }), []]);
sample('supports', 'supportsInterface', ['0xd9b67a26'], true);
sample('signer', 'signer', [], recipient);
sample('balance', 'balanceOf', [player, voucher.tokenId], 5n);
sample('balanceRecipient', 'balanceOf', [recipient, voucher.tokenId], 2n);
sample('batch', 'balanceOfBatch', [[player, player], [voucher.tokenId, 2n]], [5n, 0n]);
sample('registered', 'registered', [voucher.tokenId], true);
sample('cap', 'maxSupply', [voucher.tokenId], 100n);
sample('minted', 'totalMinted', [voucher.tokenId], 7n);
sample('uri', 'uri', [voucher.tokenId], 'ipfs://goldrush/kiem-vang.json');
sample('nonce', 'usedNonces', [voucher.nonce], false);
sample('claim', 'claimItem', [voucher, signature]);
sample('transfer', 'safeTransferFrom', [player, recipient, voucher.tokenId, voucher.amount, '0x']);
const selectors = {};
for (const fn of abi.filter(x => x.type === 'function')) selectors[fn.name] = toFunctionSelector(fn);
const errors = {};
for (const e of abi.filter(x => x.type === 'error')) errors[e.name] = toFunctionSelector(`${e.name}(${e.inputs.map(x => x.type).join(',')})`);
const fixture = { contract, player, recipient, chainId, voucher, signature, typehash, calls, results, selectors, errors };
writeFileSync(new URL('nft_abi_mau.json', import.meta.url), `${JSON.stringify(fixture, (_, v) => typeof v === 'bigint' ? v.toString() : v, 2)}\n`);
console.log(JSON.stringify({ selectors, errors, typehash }, null, 2));
