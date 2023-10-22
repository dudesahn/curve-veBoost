import pytest

DAY = 86400
WEEK = DAY * 7
YEAR = DAY * 365


@pytest.fixture(scope="session")
def ZERO_ADDRESS():
    yield "0x0000000000000000000000000000000000000000"


@pytest.fixture(scope="session")
def lock_amount():
    yield 10**24  # 1_000_000 * 10 ** 18


@pytest.fixture(scope="session")
def lock_unlock_time(chain):
    yield (chain.pending_timestamp + YEAR * 4) // WEEK * WEEK  # LOCK MAXTIME


@pytest.fixture(scope="session")
def op_ve_oracle():
    yield "0x12F407340697Ae0b177546E535b91A5be021fBF9"
