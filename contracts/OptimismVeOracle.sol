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

contract OptimismVeOracle is Ownable2Step {
    IVeCrv public constant veCRV =
        IVeCrv(0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2);

    IOptimismMessenger public constant ovmL1CrossDomainMessenger =
        IOptimismMessenger(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1);

    address public optimismVeOracle;

    function updateOptimismVeOracle(address _user) external {
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

        ovmL1CrossDomainMessenger.sendMessage(
            optimismVeOracle,
            abi.encodeWithSignature(
                "submit_state(uint256, IVeCrv.Point, IVeCrv.LockedBalance, uint256, IVeCrv.Point)",
                currentEpoch,
                globalPointStruct,
                userLockedStruct,
                userEpoch,
                userPointStruct
            ),
            1000000
        );
    }

    function _getUpdatedUserInfo(address _user)
        internal
        view
        returns (
            IVeCrv.LockedBalance memory userLockedStruct,
            IVeCrv.Point memory userPointStruct,
            uint256 userEpoch
        )
    {
        // get our lock and point struct info from veCRV
        lockedStruct = veCRV.locked(_user);

        // get our most recent epoch
        userEpoch = veCRV.user_point_epoch(_user);
        userPointStruct = veCRV.user_point_history(_user, userEpoch);
    }

    function setOptimismVeOracle(address _oracleAddress) onlyOwner {
        optimismVeOracle = _oracleAddress;
    }
}
