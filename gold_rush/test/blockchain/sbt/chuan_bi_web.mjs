// Chuẩn bị dữ liệu công khai cho sbt_web_test.dart trên node Hardhat RIÊNG.
// Không dùng private key; eth_signTypedData_v4 do tài khoản thử của node thực hiện.
// 1. Trong gold_rush_chain: npx hardhat node --hostname 127.0.0.1 --port 18545
// 2. Trong gold_rush: node test/blockchain/sbt/chuan_bi_web.mjs /private/tmp/sbt-web.json
// 3. flutter test --no-pub --platform chrome test/blockchain/sbt/sbt_web_test.dart
//      --dart-define-from-file=/private/tmp/sbt-web.json
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(new URL('../../../../gold_rush_chain/package.json', import.meta.url));
const { createPublicClient, createWalletClient, defineChain, encodeFunctionData, http, keccak256, toHex } = require('viem');
const rpcUrl = process.env.SBT_TEST_RPC ?? 'http://127.0.0.1:18545';
const url = new URL(rpcUrl);
assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname), 'Chỉ dùng RPC loopback của Hardhat thử nghiệm');
const publicClient = createPublicClient({ transport: http(rpcUrl) });
await publicClient.request({ method: 'hardhat_metadata' });
const chainId = await publicClient.getChainId();
assert.equal(chainId, 31337);
const chain = defineChain({ id: chainId, name: 'Hardhat SBT test', nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: [rpcUrl] } } });
const client = createWalletClient({ chain, transport: http(rpcUrl) });
const [owner, backendSigner, player, attacker] = await client.getAddresses();
assert.ok(attacker, 'Node cần ít nhất bốn tài khoản thử nghiệm');
const artifact = (name) => JSON.parse(readFileSync(new URL(`../../../../gold_rush_chain/artifacts/contracts/${name}.sol/${name}.json`, import.meta.url), 'utf8'));
async function confirmed(hash) {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  assert.equal(receipt.status, 'success');
  return receipt;
}
async function deploy(name, args) {
  const { abi, bytecode } = artifact(name);
  const receipt = await confirmed(await client.deployContract({ abi, bytecode, args, account: owner }));
  assert.ok(receipt.contractAddress);
  return { address: receipt.contractAddress, abi };
}
async function write(contract, name, args, account = owner) {
  await confirmed(await client.writeContract({ ...contract, functionName: name, args, account }));
}
const sbt = await deploy('ThanhTuuSBT', [owner, backendSigner]);
const shop = await deploy('CuaHangGoldRush', [backendSigner, 'uri://{id}']);
await write(shop, 'datMan', [1n, 0n, 24n]);
await write(shop, 'datMan', [2n, 5n, 23n]);
await write(shop, 'datGia', [1n, 2n]);
const now = (await publicClient.getBlock()).timestamp;
const gold = { nguoiChoi: player, man: 1n, ve: 0n, soVang: 20n, maVan: keccak256(toHex(`web-gold-${shop.address}`)), hanChot: now + 3600n };
const goldTypes = { PhieuVang: [
  { name: 'nguoiChoi', type: 'address' }, { name: 'man', type: 'uint256' },
  { name: 've', type: 'uint256' }, { name: 'soVang', type: 'uint256' },
  { name: 'maVan', type: 'bytes32' }, { name: 'hanChot', type: 'uint256' },
] };
const goldSignature = await client.signTypedData({ account: backendSigner, domain: { name: 'GoldRush', version: '2', chainId, verifyingContract: shop.address }, types: goldTypes, primaryType: 'PhieuVang', message: gold });
await write(shop, 'nhanVang', [gold, goldSignature], player);
await write(shop, 'mua', [1n], player);
await write(shop, 'vaoMan', [2n], player);
const types = { PhieuSBT: [
  { name: 'player', type: 'address' }, { name: 'achievementId', type: 'uint256' },
  { name: 'nonce', type: 'bytes32' }, { name: 'deadline', type: 'uint256' },
] };
async function voucher(id, label, signer = backendSigner, deadline = now + 3600n) {
  const p = { player, achievementId: BigInt(id), nonce: keccak256(toHex(`${sbt.address}-${label}`)), deadline };
  const signature = await client.signTypedData({ account: signer, domain: { name: 'GoldRushSBT', version: '1', chainId, verifyingContract: sbt.address }, types, primaryType: 'PhieuSBT', message: p });
  return { phieu: p, chuKy: signature, calldata: encodeFunctionData({ abi: sbt.abi, functionName: 'claimSBT', args: [p, signature] }) };
}
const goldCalls = [
  encodeFunctionData({ abi: shop.abi, functionName: 'balanceOf', args: [player, 0n] }),
  encodeFunctionData({ abi: shop.abi, functionName: 'balanceOf', args: [player, 1n] }),
  encodeFunctionData({ abi: shop.abi, functionName: 've', args: [player] }),
];
const goldBefore = [];
for (const data of goldCalls) goldBefore.push((await publicClient.call({ to: shop.address, data })).data);
const fixture = { rpcUrl, chainId, address: sbt.address, shop: shop.address, player, backendSigner,
  valid: await voucher(1, 'valid'), duplicate: await voucher(1, 'duplicate'),
  invalid: await voucher(2, 'invalid', attacker), expired: await voucher(3, 'expired', backendSigner, now - 1n),
  goldCalls, goldBefore,
};
const json = JSON.stringify(fixture, (_, value) => typeof value === 'bigint' ? value.toString() : value);
const output = process.argv[2] ?? '/private/tmp/goldrush-sbt-web.json';
writeFileSync(output, `${JSON.stringify({ SBT_WEB_FIXTURE: json }, null, 2)}\n`);
console.log(`Dữ liệu kiểm thử Web: ${output}`);
console.log(`SBT: ${sbt.address}; cửa hàng: ${shop.address}; player: ${player}`);
