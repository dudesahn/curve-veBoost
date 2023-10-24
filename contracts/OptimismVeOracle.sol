// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";

interface IOptimismMessenger {
    function xDomainMessageSender() external returns (address);
}

/**
 * @title Optimism veOracle
 * @notice This contract reports veCRV boost data received from Ethereum. Data is transmitted over Optimism's native
 *  bridge. Only the specified mainnetVeOracle may update point and lock data for a user.
 */
contract OptimismVeOracle is Ownable2Step {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    // our mainnet oracle address
    address public mainnetVeOracle;

    IOptimismMessenger public constant ovmL2CrossDomainMessenger =
        IOptimismMessenger(0x4200000000000000000000000000000000000007);

    /// Week in seconds
    uint256 constant WEEK = 1 weeks;

    /// Migrated `VotingEscrow` storage variables
    uint256 public epoch;
    mapping(address => uint256) public user_point_epoch;

    // update these to mappings
    mapping(uint256 => Point) public point_history;
    mapping(address => mapping(uint256 => Point)) public user_point_history;

    mapping(uint256 => int128) public slope_changes;
    mapping(address => LockedBalance) public locked;

    /// Log a state submission
    event SubmittedState(address _user, uint256 _userEpoch);

    constructor(address _mainnetVeOracle) {
        mainnetVeOracle = _mainnetVeOracle;
    }

    modifier onlyMainnetVeOracle() {
        require(
            msg.sender == address(ovmL2CrossDomainMessenger) &&
                ovmL2CrossDomainMessenger.xDomainMessageSender() ==
                mainnetVeOracle
        );
        _;
    }

    function balanceOf(address _user) external view returns (uint256) {
        return balanceOf(_user, block.timestamp);
    }

    function balanceOf(address _user, uint256 _timestamp)
        public
        view
        returns (uint256)
    {
        uint256 _epoch = user_point_epoch[_user];
        if (_epoch == 0) {
            return 0;
        }
        Point memory last_point = user_point_history[_user][_epoch];
        last_point.bias -=
            last_point.slope *
            abi.decode(abi.encode(_timestamp - last_point.ts), (int128));
        if (last_point.bias < 0) {
            return 0;
        }
        return abi.decode(abi.encode(last_point.bias), (uint256));
    }

    function totalSupply() external view returns (uint256) {
        return totalSupply(block.timestamp);
    }

    function totalSupply(uint256 _timestamp) public view returns (uint256) {
        Point memory last_point = point_history[epoch];
        uint256 t_i = (last_point.ts / WEEK) * WEEK; // value in the past
        for (uint256 i = 0; i < 255; i++) {
            t_i += WEEK; // + week
            int128 d_slope = 0;
            if (t_i > _timestamp) {
                t_i = _timestamp;
            } else {
                d_slope = slope_changes[t_i];
                if (d_slope == 0) {
                    break;
                }
            }
            last_point.bias -=
                last_point.slope *
                abi.decode(abi.encode(t_i - last_point.ts), (int128));
            if (t_i == _timestamp) {
                break;
            }
            last_point.slope += d_slope;
            last_point.ts = t_i;
        }

        if (last_point.bias < 0) {
            return 0;
        }
        return abi.decode(abi.encode(last_point.bias), (uint256));
    }

    // make sure to add back the onlyMainnetVeOracle once done with this testing
    function submitState(
        uint256 _epoch,
        Point memory _globalPointStruct,
        int128[8] memory _slopeChangeArray,
        address _user,
        LockedBalance memory _userLockedStruct,
        uint256 _userEpoch,
        Point memory _userPointStruct
    ) external onlyMainnetVeOracle {
        // always set the point_history structs
        point_history[_epoch] = _globalPointStruct;
        user_point_history[_user][_userEpoch] = _userPointStruct;

        // increment the epoch storage var only if fresh
        // also update slope changes too (next 8 values)
        if (_epoch > epoch) {
            epoch = _epoch;

            uint256 startTime = (_globalPointStruct.ts / WEEK) * WEEK + WEEK;

            for (uint256 i = 0; i < 8; i++) {
                slope_changes[startTime + WEEK * i] = abi.decode(
                    abi.encode(_slopeChangeArray[i]),
                    (int128)
                );
            }
        }

        // update the user point epoch and locked balance if it is newer
        if (_userEpoch > user_point_epoch[_user]) {
            user_point_epoch[_user] = _userEpoch;

            locked[_user] = _userLockedStruct;
        }

        emit SubmittedState(_user, _userEpoch);
    }

    /**
     * @notice Update the Ethereum veOracle contract address.
     * @dev May only be called by owner.
     * @param _oracleAddress The address for our veOracle on Ethereum.
     */
    function setMainnetVeOracle(address _oracleAddress) external onlyOwner {
        mainnetVeOracle = _oracleAddress;
    }
}
