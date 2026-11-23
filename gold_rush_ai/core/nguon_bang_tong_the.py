"""Read-only sources for overall ranking; all badge calls use one block."""
import json
import re
import urllib.request

import config
from core.qua_tang import goi_rpc


def tong_vang(vouchers, tickets, chain_id, wallets):
    registered = {w.lower() for w in wallets}
    starts = {r['ma_van']: r for r in tickets if r.get('chain_id') == chain_id}
    totals, seen = {}, set()
    for voucher in vouchers:
        run = voucher.get('ma_van')
        wallet = str(voucher.get('vi', '')).lower()
        ticket = starts.get(run)
        amount = voucher.get('so_vang_goc', voucher.get('so_vang'))
        if (voucher.get('chain_id') != chain_id or wallet not in registered
                or not ticket or str(ticket.get('vi', '')).lower() != wallet
                or type(voucher.get('man')) is not int or not 1 <= voucher['man'] <= 20
                or voucher['man'] != ticket.get('man') or voucher.get('ve') != ticket.get('ve')
                or type(amount) is not int or amount <= 0 or run in seen):
            continue
        seen.add(run)
        totals[wallet] = totals.get(wallet, 0) + amount
    return totals


def _batch_rpc(calls):
    if not config.BLOCKCHAIN_RPC_URL:
        raise RuntimeError('RPC not configured')
    request = urllib.request.Request(config.BLOCKCHAIN_RPC_URL,
        data=json.dumps(calls).encode(), headers={'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(request, timeout=config.RPC_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode('utf-8'))


def doc_huy_hieu(wallets, chain_id, contract, *, rpc=goi_rpc, batch=_batch_rpc):
    if not re.fullmatch(r'0x[0-9a-fA-F]{40}', contract or ''):
        raise ValueError('SBT contract not configured')
    if int(rpc('eth_chainId', []), 16) != chain_id:
        raise ValueError('RPC chain mismatch')
    block = rpc('eth_blockNumber', [])
    if not isinstance(block, str) or not re.fullmatch(r'0x[0-9a-fA-F]+', block):
        raise ValueError('Invalid block number')
    code = rpc('eth_getCode', [contract, block])
    if not isinstance(code, str) or not re.fullmatch(r'0x[0-9a-fA-F]+', code) or int(code[2:], 16) == 0:
        raise ValueError('SBT contract unavailable')
    result, requests, owners = {}, [], {}
    for wallet in wallets:
        if not re.fullmatch(r'0x[0-9a-fA-F]{40}', wallet):
            raise ValueError('Invalid registered wallet')
        wallet = wallet.lower()
        result[wallet] = []
        for badge in range(1, 6):
            request_id = len(requests) + 1
            owners[request_id] = (wallet, badge)
            data = '0xab5eba16' + wallet[2:].rjust(64, '0') + f'{badge:064x}'
            requests.append(dict(jsonrpc='2.0', id=request_id, method='eth_call',
                                 params=[{'to': contract, 'data': data}, block]))
    for offset in range(0, len(requests), 50):
        chunk = requests[offset:offset+50]
        responses = batch(chunk)
        if not isinstance(responses, list) or len(responses) != len(chunk):
            raise RuntimeError('Incomplete SBT snapshot')
        expected = {r['id'] for r in chunk}
        for response in responses:
            if not isinstance(response, dict) or response.get('id') not in expected or 'error' in response:
                raise RuntimeError('Invalid SBT response')
            expected.remove(response['id'])
            value = response.get('result')
            if not isinstance(value, str) or not re.fullmatch(r'0x[0-9a-fA-F]{64}', value) or int(value, 16) not in (0, 1):
                raise ValueError('Invalid hasAchievement ABI bool')
            if int(value, 16):
                wallet, badge = owners[response['id']]
                result[wallet].append(badge)
        if expected:
            raise RuntimeError('Missing SBT result')
    return {wallet: sorted(ids) for wallet, ids in result.items()}
