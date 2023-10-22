import pytest

pytest_plugins = [
    "fixtures.accounts",
    "fixtures.constants",
    "fixtures.deployments",
    "fixtures.functions",
]



@pytest.fixture(scope="function")
def veboost_v3(alice, project, op_ve_oracle):
    yield project.BoostV3Sidechain.deploy(op_ve_oracle, sender=alice)