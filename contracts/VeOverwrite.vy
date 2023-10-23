# @version 0.3.9
"""
@title Boost Overwrite v1
@author YearnFi
@notice Check if we need to override the ve balance of one address with another, and report that to our veBOOST. This
 contract sits between our veBOOST and veOracle, reading through oracle values and updating as needed when an address
 does have an overwrite.
"""


interface VotingEscrow:
    def balanceOf(_user: address) -> uint256: view
    def totalSupply() -> uint256: view
    def locked(_user: address) -> LockedBalance: view


event Overwrite:
    _mainnet_locker: indexed(address)
    _local_locker: indexed(address)

event UpdateGovernance:
    governance: address # New active governance

event NewPendingGovernance:
    pendingGovernance: indexed(address)


struct LockedBalance:
    amount: int128
    end: uint256


NAME: constant(String[32]) = "Vote-Escrowed Overwrite"
SYMBOL: constant(String[8]) = "veOverwrite"
VERSION: constant(String[8]) = "v1.0.0"

VE: immutable(address)
governance: public(address)
pendingGovernance: address

overwrites: public(HashMap[address, address])

@external
def __init__(_ve: address, _governance: address):
    VE = _ve
    self.governance = _governance
    log UpdateGovernance(_governance)


@external
def setOverwrite(_mainnet_locker: address, _local_locker: address):
    """
    @notice
        Creates an overwrite for the given address. Local address will be treated
        as if it has the veCRV balance of the mainnet address. Especially useful
        if a mainnet locker cannot be accessed on other chains. 

        This may only be called by governance.
    @param _mainnet_locker The address to check for veCRV balance.
    @param _local_locker The address to overwrite with our mainnet veCRV balance.
    """
    assert msg.sender == self.governance
    self.overwrites[_local_locker] = _mainnet_locker
    log Overwrite(_mainnet_locker, _local_locker)


# 2-phase commit for a change in governance
@external
def setGovernance(governance: address):
    """
    @notice
        Nominate a new address to use as governance.

        The change does not go into effect immediately. This function sets a
        pending change, and the governance address is not updated until
        the proposed governance address has accepted the responsibility.

        This may only be called by the current governance address.
    @param governance The address requested to take over governance.
    """
    assert msg.sender == self.governance
    log NewPendingGovernance(governance)
    self.pendingGovernance = governance


@external
def acceptGovernance():
    """
    @notice
        Once a new governance address has been proposed using setGovernance(),
        this function may be called by the proposed address to accept the
        responsibility of taking over governance for this contract.

        This may only be called by the proposed governance address.
    @dev
        setGovernance() should be called by the existing governance address,
        prior to calling this function.
    """
    assert msg.sender == self.pendingGovernance
    self.governance = msg.sender
    log UpdateGovernance(msg.sender)


@view
@internal
def _check_overwrite(_user: address) -> address:
    """
    @notice Check if we need to override the ve balance of one address with another
    @param _user User address to check
    """
    user_overwrite: address = _user
    if self.overwrites[_user] != ZERO_ADDRESS:
        user_overwrite = self.overwrites[_user]
    
    return user_overwrite


@view
@internal
def _balance_of(_user: address) -> uint256:
    # check for an overwrite
    user_overwrite: address = _user
    user_overwrite = self._check_overwrite(_user)

    amount: uint256 = VotingEscrow(VE).balanceOf(user_overwrite)
    return amount


@view
@external
def locked(_user: address) -> LockedBalance:
    # check for an overwrite
    user_overwrite: address = _user
    user_overwrite = self._check_overwrite(_user)
    return VotingEscrow(VE).locked(user_overwrite)


@view
@external
def balanceOf(_user: address) -> uint256:
    return self._balance_of(_user)


@view
@external
def totalSupply() -> uint256:
    return VotingEscrow(VE).totalSupply()


@pure
@external
def name() -> String[32]:
    return NAME


@pure
@external
def symbol() -> String[8]:
    return SYMBOL


@pure
@external
def VE() -> address:
    return VE