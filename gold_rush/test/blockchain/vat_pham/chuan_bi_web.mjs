// Chỉ chạy trên node Hardhat riêng: npx hardhat node --hostname 127.0.0.1 --port 18545
// node test/blockchain/vat_pham/chuan_bi_web.mjs /private/tmp/nft-web.json
// flutter test --no-pub --platform chrome test/blockchain/vat_pham/nft_web_test.dart
//   --dart-define-from-file=/private/tmp/nft-web.json
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../../../../gold_rush_chain/package.json', import.meta.url));
const { createPublicClient, createWalletClient, defineChain, http, keccak256, toHex } = require('viem');
const rpcUrl = process.env.NFT_TEST_RPC ?? 'http://127.0.0.1:18545';
assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(new URL(rpcUrl).hostname), 'Chỉ dùng RPC loopback thử nghiệm');
const pc = createPublicClient({ transport: http(rpcUrl) });
await pc.request({ method: 'hardhat_metadata' });
const chainId = await pc.getChainId();
assert.equal(chainId, 31337);
const chain = defineChain({ id: chainId, name: 'Hardhat NFT test', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [rpcUrl] } } });
const wallet = createWalletClient({ chain, transport: http(rpcUrl) });
const [owner, backendSigner, player, recipient, attacker] = await wallet.getAddresses();
assert.ok(attacker);
const artifact = JSON.parse(readFileSync(new URL('../../../../gold_rush_chain/artifacts/contracts/VatPhamGoldRush.sol/VatPhamGoldRush.json', import.meta.url)));
async function confirmed(hash) {
  const receipt = await pc.waitForTransactionReceipt({ hash }); assert.equal(receipt.status, 'success'); return receipt;
}
const deployed = await confirmed(await wallet.deployContract({ abi: artifact.abi, bytecode: artifact.bytecode, args: [owner, backendSigner], account: owner }));
const address = deployed.contractAddress;
assert.ok(address);
const tokenId = (1n << 200n) + 1n;
const max = (1n << 256n) - 1n;
await confirmed(await wallet.writeContract({ address, abi: artifact.abi, functionName: 'registerItem', args: [tokenId, 'ipfs://goldrush/kiem-vang.json', max], account: owner }));
const now = (await pc.getBlock()).timestamp;
const types = { PhieuVatPham: [
  { name: 'player', type: 'address' }, { name: 'tokenId', type: 'uint256' },
  { name: 'amount', type: 'uint256' }, { name: 'nonce', type: 'bytes32' }, { name: 'deadline', type: 'uint256' },
] };
async function voucher(label, signer = backendSigner, deadline = now + 3600n) {
  const p = { player, tokenId, amount: 3n, nonce: keccak256(toHex(`${address}-${label}`)), deadline };
  const signature = await wallet.signTypedData({ account: signer, domain: { name: 'GoldRushEquipment', version: '1', chainId, verifyingContract: address }, types, primaryType: 'PhieuVatPham', message: p });
  return { phieu: p, chuKy: signature };
}
const fixture = { rpcUrl, chainId, address, player, recipient, tokenId, valid: await voucher('valid'), rejected: await voucher('user-reject'), invalid: await voucher('invalid', attacker), expired: await voucher('expired', backendSigner, now - 1n) };
const output = process.argv[2] ?? '/private/tmp/goldrush-nft-web.json';
writeFileSync(output, `${JSON.stringify({ NFT_WEB_FIXTURE: JSON.stringify(fixture, (_, v) => typeof v === 'bigint' ? v.toString() : v) }, null, 2)}\n`);
console.log(`Fixture: ${output}; NFT: ${address}; player: ${player}`);
