import pytest

from core.nguon_bang_tong_the import tong_vang, doc_huy_hieu, doc_so_du_va_huy_hieu

WALLET = '0x' + 'a' * 40
CONTRACT = '0x' + 'b' * 40


def test_lifetime_gold_unique_verified_reward_ledger_not_balances():
    ticket = dict(ma_van='win', chain_id=31337, vi=WALLET, man=1, ve=0)
    voucher = dict(ticket, so_vang=20, so_vang_goc=25)
    assert tong_vang([voucher, voucher], [ticket], 31337, {WALLET}) == {WALLET: 25}
    for bad in [dict(voucher, chain_id=1), dict(voucher, vi='0x'+'c'*40),
                dict(voucher, ve=3), dict(voucher, man=22),
                {k: v for k, v in voucher.items() if k != 'chain_id'}]:
        assert tong_vang([bad], [ticket], 31337, {WALLET}) == {}
    assert tong_vang([voucher], [], 31337, {WALLET}) == {}


def test_badges_use_all_wallets_one_verified_chain_contract_and_block():
    calls = []
    def rpc(method, params):
        calls.append((method, params))
        return {'eth_chainId': '0x7a69', 'eth_blockNumber': '0x123', 'eth_getCode': '0x6001'}[method]
    def batch(requests):
        assert len(requests) == 10
        assert all(r['method'] == 'eth_call' and r['params'][1] == '0x123' for r in requests)
        assert all(r['params'][0]['to'] == CONTRACT for r in requests)
        return [dict(id=r['id'], jsonrpc='2.0', result='0x' + f'{int(i in (0, 4, 9)):064x}') for i, r in reversed(list(enumerate(requests)))]
    wallets = [WALLET, '0x'+'c'*40]
    assert doc_huy_hieu(wallets, 31337, CONTRACT, rpc=rpc, batch=batch) == {WALLET: [1, 5], wallets[1]: [5]}
    assert ('eth_getCode', [CONTRACT, '0x123']) in calls


def test_real_token0_balances_and_badges_for_all_35_wallets_at_one_block():
    shop = '0x'+'d'*40
    wallets = [f'0x{i:040x}' for i in range(35)]
    calls, chunks = [], []
    def rpc(method, params):
        calls.append((method, params))
        return {'eth_chainId':'0x7a69', 'eth_blockNumber':'0x123', 'eth_getCode':'0x6001'}[method]
    def batch(requests):
        chunks.append(len(requests))
        assert len(requests) <= 50
        response = []
        for r in requests:
            call, block = r['params']
            assert block == '0x123'
            wallet_index = int(call['data'][10:74],16)
            if call['data'].startswith('0x00fdd58e'):
                assert call['to'] == shop and int(call['data'][74:],16) == 0
                value = 10**40+wallet_index
            else:
                assert call['to'] == CONTRACT and call['data'].startswith('0xab5eba16')
                value = int(int(call['data'][74:],16) == 2)
            response.append(dict(id=r['id'],result='0x'+f'{value:064x}'))
        return list(reversed(response))
    balances, badges = doc_so_du_va_huy_hieu(wallets,31337,shop,CONTRACT,rpc=rpc,batch=batch)
    assert balances == {w:10**40+i for i,w in enumerate(wallets)}
    assert badges == {w:[2] for w in wallets}
    assert chunks == [50,50,50,50,10]
    assert ('eth_getCode',[shop,'0x123']) in calls
    assert ('eth_getCode',[CONTRACT,'0x123']) in calls


@pytest.mark.parametrize('problem',['no-shop','wrong-chain','missing-shop-code','partial','bad-balance','rpc-error'])
def test_gold_source_failure_never_becomes_zero(problem):
    shop = '0x'+'d'*40
    def rpc(method, params):
        if method == 'eth_chainId': return '0x1' if problem == 'wrong-chain' else '0x7a69'
        if method == 'eth_blockNumber': return '0x123'
        return '0x' if problem == 'missing-shop-code' and params[0] == shop else '0x6001'
    def batch(requests):
        if problem == 'partial': return []
        return [dict(id=r['id'],result='0x' if problem == 'bad-balance' else '0x'+'0'*64,
                     **({'error':{}} if problem == 'rpc-error' else {})) for r in requests]
    with pytest.raises((ValueError,RuntimeError)):
        doc_so_du_va_huy_hieu([WALLET],31337,'' if problem == 'no-shop' else shop,CONTRACT,rpc=rpc,batch=batch)


@pytest.mark.parametrize('problem', ['wrong-chain', 'no-code', 'partial', 'bad-bool', 'rpc-error'])
def test_badge_failure_does_not_fabricate_unowned_badges(problem):
    def rpc(method, params):
        if method == 'eth_chainId': return '0x1' if problem == 'wrong-chain' else '0x7a69'
        if method == 'eth_blockNumber': return '0x1'
        return '0x' if problem == 'no-code' else '0x6001'
    def batch(requests):
        if problem == 'partial': return []
        return [dict(id=r['id'], result='0x' + f'{2 if problem == "bad-bool" else 0:064x}',
                     **({'error': {'message': 'failure'}} if problem == 'rpc-error' else {})) for r in requests]
    with pytest.raises((ValueError, RuntimeError)):
        doc_huy_hieu([WALLET], 31337, CONTRACT, rpc=rpc, batch=batch)
