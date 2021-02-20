pragma solidity 0.7.3;

import "../interfaces/DeltaTokenInterface.sol";

contract Utils {
    DeltaTokenInterface deltaToken;

    constructor(address _deltaToken) {
        deltaToken = DeltaTokenInterface(_deltaToken);
    }

    function batchTokenTransfer(
        address[] memory _tos,
        uint256[] memory _amounts
    ) public {
        for (uint256 i = 0; i < _tos.length; i++) {
            deltaToken.transferFrom(msg.sender, _tos[i], _amounts[i]);
        }
    }
}
