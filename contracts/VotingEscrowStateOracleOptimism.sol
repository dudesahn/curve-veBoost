// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";

contract VotingEscrowStateOracleOptimism is Ownable2Step {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

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

    ////////////////////////////////////////////////////////////////////////////// NEW STUFFFFFFFFFF

    // our mainnet oracle address
    address public mainnetVeOracle;

    //////////////////////////////////////////////////////////////////////////////

    /// Week in seconds
    uint256 constant WEEK = 1 weeks;

    /// Migrated `VotingEscrow` storage variables
    uint256 public epoch;
    Point[100000000000000000000000000000] public point_history;
    mapping(address => uint256) public user_point_epoch;
    mapping(address => Point[1000000000]) public user_point_history;

    mapping(uint256 => int128) public slope_changes;
    mapping(address => LockedBalance) public locked;
    mapping(bytes32 => bool) public submitted_hashes;

    /// Log a state submission
    event SubmittedState(address _user, address _userEpoch);

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

    function submit_state(
        uint256 _epoch,
        Point memory _globalPointStruct,
        LockedBalance _userLockedStruct,
        uint256 _userEpoch,
        Point memory _userPointStruct
    ) external onlyMainnetVeOracle {
        /// incrememt the epoch storage var only if fresh
        /// also update slope changes too
        if (_epoch > epoch) {
            epoch = _epoch;

            for (uint256 i = 0; i < 8; i++) {
                slope_changes[start_time + WEEK * i] = abi.decode(
                    abi.encode(slot_slope_changes[i].value),
                    (int128)
                );
            }
        }
        /// always set the point_history structs
        point_history[_epoch] = Point(_globalPointStruct);

        // update the user point epoch and locked balance if it is newer
        if (_userEpoch > user_point_epoch[_user]) {
            user_point_epoch[_user] = _userEpoch;

            locked[_user] = LockedBalance(_userLockedStruct);
        }
        /// always set the point_history structs
        user_point_history[_user][_userEpoch] = Point(_userPointStruct);

        emit SubmittedState(_user, _userEpoch);
    }

    function setMainnetVeOracle(address _oracleAddress) onlyOwner {
        mainnetVeOracle = _oracleAddress;
    }
}
