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
    _mainnetLocker: indexed(address)
    _localLocker: indexed(address)

event UpdateGovernance:
    governance: address # New active governance

event NewPendingGovernance:
    pendingGovernance: indexed(address)


struct LockedBalance:
    amount: int128
    end: uint256


NAME: constant(String[32]) = "Vote-Escrowed Overwrite"
SYMBOL: constant(String[16]) = "veOverwrite"
VERSION: constant(String[8]) = "v1.0.0"
DEAD_ADDRESS: constant(address) = 0x000000000000000000000000000000000000dEaD

VE: immutable(address)
governance: public(address)
pendingGovernance: address

# L2 addrress => mainnet address
overwriteBalanceOfUserWith: public(HashMap[address, address])

# mainnet addrress => L2 address
mainnetLockerOverwriteTo: public(HashMap[address, address])

@external
def __init__(_ve: address, _governance: address):
    VE = _ve
    self.governance = _governance
    log UpdateGovernance(_governance)


@external
def setOverwrite(_mainnetLocker: address, _localLocker: address):
    """
    @notice
        Creates an overwrite for the given address. Local address will be treated as if it has the veCRV balance of the
        mainnet address. Especially useful if a mainnet locker cannot be accessed on other chains.
        
        To "reclaim" the boost owned by a given L1 address to be used by the same L2 address, pass ZERO_ADDRESS as the
        _localLocker.

        This may only be called by governance.
    @param _mainnetLocker The address to check for veCRV balance.
    @param _localLocker The address to overwrite with our mainnet veCRV balance.
    """
    assert msg.sender == self.governance, "Only governance can call"
    assert self.overwriteBalanceOfUserWith[_localLocker] != _mainnetLocker, "This overwrite is already set"
    
    # check if another mainnet address is currently delegating to this _localLocker
    current_overwrite_to_localLocker: address = self.overwriteBalanceOfUserWith[_localLocker]
    if current_overwrite_to_localLocker != ZERO_ADDRESS:
        self.overwriteBalanceOfUserWith[current_overwrite_to_localLocker] = ZERO_ADDRESS
    
    # check if _mainnetLocker address is already overwriting another address
    current_overwrite_recipient: address = self.mainnetLockerOverwriteTo[_mainnetLocker]
    
    if current_overwrite_recipient != ZERO_ADDRESS:
        # if _mainnetLocker is currently overwriting another address, sever the link between the two
        self.overwriteBalanceOfUserWith[current_overwrite_recipient] = ZERO_ADDRESS
    else:
        # overwrite our _mainnetLocker address with zero balance, but only if it isn't already zeroed
        self.overwriteBalanceOfUserWith[_mainnetLocker] = DEAD_ADDRESS
    
    # now do the core overwrites
    self.overwriteBalanceOfUserWith[_localLocker] = _mainnetLocker
    self.mainnetLockerOverwriteTo[_mainnetLocker] = _localLocker
    log Overwrite(_mainnetLocker, _localLocker)


# 2-phase commit for a change in governance
@external
def setGovernance(governance: address):
    """
    @notice
        Nominate a new address to use as governance.

        The change does not go into effect immediately. This function sets a pending change, and the governance address
        is not updated until he proposed governance address has accepted the responsibility.

        This may only be called by the current governance address.
    @param governance The address requested to take over governance.
    """
    assert msg.sender == self.governance, "Only governance can call"
    log NewPendingGovernance(governance)
    self.pendingGovernance = governance


@external
def acceptGovernance():
    """
    @notice
        Once a new governance address has been proposed using setGovernance(), this function may be called by the
        proposed address to accept the responsibility of taking over governance for this contract.

        This may only be called by the proposed governance address.
    @dev
        setGovernance() should be called by the existing governance address, prior to calling this function.
    """
    assert msg.sender == self.governance, "Only pendingGovernance can call"
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
    if self.overwriteBalanceOfUserWith[_user] != ZERO_ADDRESS:
        user_overwrite = self.overwriteBalanceOfUserWith[_user]
    
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
def symbol() -> String[16]:
    return SYMBOL


@pure
@external
def VE() -> address:
    return VE