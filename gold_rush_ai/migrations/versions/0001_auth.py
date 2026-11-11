"""Create the four Auth tables and their constraints.

Revision ID: 0001_auth
Revises: None
Create Date: 2026-11-06 14:15:37.396570+00:00

Schema statements are a snapshot, not runtime lookups of Base.metadata.
UTCDateTime and ChainId retain the adapters used by the existing models.
UUID/created_at Python defaults belong to the ORM; only avatar has a server
default in this schema. A downgrade removes Auth tables and their data.

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import auth.models

# revision identifiers, used by Alembic.
revision: str = '0001_auth'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('users',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('wallet_address', sa.String(length=42), nullable=False),
    sa.Column('username', sa.String(length=20), nullable=False),
    sa.Column('username_key', sa.String(length=60), nullable=False),
    sa.Column('avatar', sa.String(length=32), server_default='george', nullable=False),
    sa.Column('created_at', auth.models.UTCDateTime(), nullable=False),
    sa.CheckConstraint("length(wallet_address) = 42 AND substr(wallet_address, 1, 2) = '0x' AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(substr(wallet_address, 3), '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name=op.f('ck_users_wallet_format')),
    sa.CheckConstraint('length(avatar) BETWEEN 1 AND 32', name=op.f('ck_users_avatar_length')),
    sa.CheckConstraint('length(username) BETWEEN 3 AND 20', name=op.f('ck_users_username_length')),
    sa.CheckConstraint('length(username_key) BETWEEN 1 AND 60', name=op.f('ck_users_username_key_length')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_users')),
    sa.UniqueConstraint('username_key', name=op.f('uq_users_username_key')),
    sa.UniqueConstraint('wallet_address', name=op.f('uq_users_wallet_address'))
    )
    op.create_table('auth_challenges',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('nonce', sa.String(length=64), nullable=False),
    sa.Column('wallet_address', sa.String(length=42), nullable=False),
    sa.Column('chain_id', auth.models.ChainId(), nullable=False),
    sa.Column('domain', sa.String(length=255), nullable=False),
    sa.Column('uri', sa.String(length=2048), nullable=False),
    sa.Column('message', sa.Text(), nullable=False),
    sa.Column('browser_binding_hash', sa.String(length=64), nullable=False),
    sa.Column('issued_at', auth.models.UTCDateTime(), nullable=False),
    sa.Column('expires_at', auth.models.UTCDateTime(), nullable=False),
    sa.Column('consumed_at', auth.models.UTCDateTime(), nullable=True),
    sa.CheckConstraint("length(browser_binding_hash) = 64 AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(browser_binding_hash, '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name=op.f('ck_auth_challenges_browser_binding_hash_format')),
    sa.CheckConstraint("length(chain_id) = 78 AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(chain_id, '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', '') = '' AND chain_id BETWEEN '000000000000000000000000000000000000000000000000000000000000000000000000000001' AND '115792089237316195423570985008687907853269984665640564039457584007913129639935'", name=op.f('ck_auth_challenges_chain_id_range')),
    sa.CheckConstraint("length(wallet_address) = 42 AND substr(wallet_address, 1, 2) = '0x' AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(substr(wallet_address, 3), '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name=op.f('ck_auth_challenges_wallet_format')),
    sa.CheckConstraint('consumed_at IS NULL OR consumed_at >= issued_at', name=op.f('ck_auth_challenges_consumption_after_issue')),
    sa.CheckConstraint('expires_at > issued_at', name=op.f('ck_auth_challenges_expiry_after_issue')),
    sa.CheckConstraint('length(domain) BETWEEN 1 AND 255', name=op.f('ck_auth_challenges_domain_length')),
    sa.CheckConstraint('length(message) BETWEEN 1 AND 4096', name=op.f('ck_auth_challenges_message_length')),
    sa.CheckConstraint('length(nonce) BETWEEN 8 AND 64', name=op.f('ck_auth_challenges_nonce_length')),
    sa.CheckConstraint('length(uri) BETWEEN 1 AND 2048', name=op.f('ck_auth_challenges_uri_length')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_auth_challenges')),
    sa.UniqueConstraint('nonce', name=op.f('uq_auth_challenges_nonce'))
    )
    op.create_index(op.f('ix_auth_challenges_expires_at'), 'auth_challenges', ['expires_at'], unique=False)
    op.create_index('ix_auth_challenges_wallet_issued', 'auth_challenges', ['wallet_address', 'issued_at'], unique=False)
    op.create_table('auth_sessions',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('token_hash', sa.String(length=64), nullable=False),
    sa.Column('purpose', sa.String(length=16), nullable=False),
    sa.Column('wallet_address', sa.String(length=42), nullable=False),
    sa.Column('chain_id', auth.models.ChainId(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=True),
    sa.Column('created_at', auth.models.UTCDateTime(), nullable=False),
    sa.Column('expires_at', auth.models.UTCDateTime(), nullable=False),
    sa.Column('revoked_at', auth.models.UTCDateTime(), nullable=True),
    sa.CheckConstraint("(purpose = 'registration' AND user_id IS NULL) OR (purpose = 'authenticated' AND user_id IS NOT NULL)", name=op.f('ck_auth_sessions_purpose_user_consistency')),
    sa.CheckConstraint("length(chain_id) = 78 AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(chain_id, '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', '') = '' AND chain_id BETWEEN '000000000000000000000000000000000000000000000000000000000000000000000000000001' AND '115792089237316195423570985008687907853269984665640564039457584007913129639935'", name=op.f('ck_auth_sessions_chain_id_range')),
    sa.CheckConstraint("length(token_hash) = 64 AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(token_hash, '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name=op.f('ck_auth_sessions_token_hash_format')),
    sa.CheckConstraint("length(wallet_address) = 42 AND substr(wallet_address, 1, 2) = '0x' AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(substr(wallet_address, 3), '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name=op.f('ck_auth_sessions_wallet_format')),
    sa.CheckConstraint('expires_at > created_at', name=op.f('ck_auth_sessions_expiry_after_creation')),
    sa.CheckConstraint('revoked_at IS NULL OR revoked_at >= created_at', name=op.f('ck_auth_sessions_revocation_after_creation')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_auth_sessions_user_id_users'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_auth_sessions')),
    sa.UniqueConstraint('token_hash', name=op.f('uq_auth_sessions_token_hash'))
    )
    op.create_index(op.f('ix_auth_sessions_expires_at'), 'auth_sessions', ['expires_at'], unique=False)
    op.create_index(op.f('ix_auth_sessions_user_id'), 'auth_sessions', ['user_id'], unique=False)
    op.create_index(op.f('ix_auth_sessions_wallet_address'), 'auth_sessions', ['wallet_address'], unique=False)
    op.create_table('game_run_owners',
    sa.Column('ma_van', sa.String(length=64), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('created_at', auth.models.UTCDateTime(), nullable=False),
    sa.CheckConstraint('length(ma_van) BETWEEN 8 AND 64', name=op.f('ck_game_run_owners_ma_van_length')),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_game_run_owners_user_id_users'), ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('ma_van', name=op.f('pk_game_run_owners'))
    )
    op.create_index(op.f('ix_game_run_owners_user_id'), 'game_run_owners', ['user_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_game_run_owners_user_id'), table_name='game_run_owners')
    op.drop_table('game_run_owners')
    op.drop_index(op.f('ix_auth_sessions_wallet_address'), table_name='auth_sessions')
    op.drop_index(op.f('ix_auth_sessions_user_id'), table_name='auth_sessions')
    op.drop_index(op.f('ix_auth_sessions_expires_at'), table_name='auth_sessions')
    op.drop_table('auth_sessions')
    op.drop_index('ix_auth_challenges_wallet_issued', table_name='auth_challenges')
    op.drop_index(op.f('ix_auth_challenges_expires_at'), table_name='auth_challenges')
    op.drop_table('auth_challenges')
    op.drop_table('users')
