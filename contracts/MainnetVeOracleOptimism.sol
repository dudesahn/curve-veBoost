// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts@4.9.3/access/Ownable2Step.sol";

interface IVeCrv {
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

    function epoch() external view returns (uint256);

    function point_history(uint256) external view returns (Point memory);

    function slope_changes(uint256) external view returns (int128);

    function locked(address _user) external view returns (LockedBalance memory);

    function user_point_epoch(address _user) external view returns (uint256);

    function user_point_history(address _user, uint256 _epoch)
        external
        view
        returns (Point memory);
}

interface IOptimismMessenger {
    function sendMessage(
        address _target,
        bytes memory _message,
        uint32 _gasLimit
    ) external;
}

/**
 * @title Mainnet veOracle Optimism
 * @notice This contract reads data from Curve's veCRV contract for a given user, and pushes that data to Optimism to be
 *  read and used for determining boost for Curve gauges on Optimism. Additionally, overwrites can be set for users such
 *  that an L1 veCRV balance will be written to a different address on the L2.
 */
contract MainnetVeOracleOptimism is Ownable2Step {
    /// @notice Ethereum veCRV contract; pull all of our info from here
    IVeCrv public constant veCRV =
        IVeCrv(0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2);

    /// @notice The address of Optimism's messenger contract on L1
    IOptimismMessenger public constant ovmL1CrossDomainMessenger =
        IOptimismMessenger(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1);

    /// @notice The address of our veOracle on Optimism
    address public optimismVeOracle;

    /// Week in seconds
    uint256 constant WEEK = 1 weeks;

    /**
     * @notice Update the state of the Optimism veOracle for a given user.
     * @param _user The user whose L1 veCRV state to push to veOracle on Optimism.
     */
    function pushVeOracleUpdateOptimism(address _user) public {
        if (optimismVeOracle == address(0)) {
            revert("Set optimismVeOracle address first");
        }

        // here we should pull all of the relevant params we need from veCRV to send to the L2
        (
            IVeCrv.LockedBalance memory userLockedStruct,
            IVeCrv.Point memory userPointStruct,
            uint256 userEpoch
        ) = _getUpdatedUserInfo(_user);

        // pull our global point history struct
        uint256 currentEpoch = veCRV.epoch();
        IVeCrv.Point memory globalPointStruct = veCRV.point_history(
            currentEpoch
        );

        // generate slope changes
        int128[8] memory slopeChanges;
        uint256 startTime = (globalPointStruct.ts / WEEK) * WEEK + WEEK;
        for (uint256 i = 0; i < 8; i++) {
            slopeChanges[i] = veCRV.slope_changes(startTime + WEEK * i);
        }

        // this call will change based on the L2 we are pushing the message to
        ovmL1CrossDomainMessenger.sendMessage(
            optimismVeOracle,
            abi.encodeWithSignature(
                "submitState(uint256,(int128,int128,uint256,uint256),int128[8],address,(int128,uint256),uint256,(int128,int128,uint256,uint256))",
                currentEpoch,
                globalPointStruct,
                slopeChanges,
                _user,
                userLockedStruct,
                userEpoch,
                userPointStruct
            ),
            1000000
        );
    }

    /**
     * @notice Pull info from the veCRV contract for a given user address.
     * @param _user The user whose data to push to Optimism's veOracle.
     * @return userLockedStruct Struct containing the user's lock info.
     * @return userPointStruct Struct containing the user's point info (bias, slope, etc.).
     * @return userEpoch Current epoch for a given user.
     */
    function _getUpdatedUserInfo(address _user)
        internal
        view
        returns (
            IVeCrv.LockedBalance memory userLockedStruct,
            IVeCrv.Point memory userPointStruct,
            uint256 userEpoch
        )
    {
        // get our lock and point struct, as well as our latest user epoch, from veCRV
        userLockedStruct = veCRV.locked(_user);
        userEpoch = veCRV.user_point_epoch(_user);
        userPointStruct = veCRV.user_point_history(_user, userEpoch);
    }

    /**
     * @notice Update the Optimism veOracle contract address.
     * @dev May only be called by owner.
     * @param _oracleAddress The address for our new veOracle on Optimism.
     */
    function setVeOracleOptimism(address _oracleAddress) external onlyOwner {
        optimismVeOracle = _oracleAddress;
    }
}
