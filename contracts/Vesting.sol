// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "./openzeppelin/Ownable.sol";
import "./openzeppelin/SafeMath.sol";
import "./interfaces/DeltaTokenInterface.sol";

contract VestingWallet is Ownable {

	using SafeMath for uint256;

    mapping(address => VestingSchedule) public schedules;        // vesting schedules for given addresses
    mapping(address => address) public addressChangeRequests;    // requested address changes

    DeltaTokenInterface vestingToken;

    event VestingScheduleRegistered(
        address indexed registeredAddress,
        address depositor,
        uint startTimeInSec,
        uint cliffTimeInSec,
        uint endTimeInSec,
        uint totalAmount
    );
    event VestingScheduleConfirmed(
        address indexed registeredAddress,
        address depositor,
        uint startTimeInSec,
        uint cliffTimeInSec,
        uint endTimeInSec,
        uint totalAmount
    );
    event Withdrawal(address indexed registeredAddress, uint amountWithdrawn);
    event VestingEndedByOwner(address indexed registeredAddress, uint amountWithdrawn, uint amountRefunded);
    event AddressChangeRequested(address indexed oldRegisteredAddress, address indexed newRegisteredAddress);
    event AddressChangeConfirmed(address indexed oldRegisteredAddress, address indexed newRegisteredAddress);

    struct VestingSchedule {
        uint startTimeInSec;
        uint cliffTimeInSec;
        uint endTimeInSec;
        uint totalAmount;
        uint totalAmountWithdrawn;
        address depositor;
        bool isConfirmed;
    }

    modifier addressRegistered(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(vestingSchedule.depositor != address(0), "addressRegistered");
        _;
    }

    modifier addressNotRegistered(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(vestingSchedule.depositor == address(0), "addressNotRegistered");
        _;
    }

    modifier vestingScheduleConfirmed(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(vestingSchedule.isConfirmed, "vestingScheduleConfirmed");
        _;
    }

    modifier vestingScheduleNotConfirmed(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(!vestingSchedule.isConfirmed, "vestingScheduleNotConfirmed");
        _;
    }

    modifier pendingAddressChangeRequest(address target) {
        require(addressChangeRequests[target] != address(0), "pendingAddressChangeRequest");
        _;
    }

    modifier pastCliffTime(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(block.timestamp > vestingSchedule.cliffTimeInSec, "pastCliffTime");
        _;
    }

    modifier validVestingScheduleTimes(uint startTimeInSec, uint cliffTimeInSec, uint endTimeInSec) {
        require(cliffTimeInSec >= startTimeInSec, "cliff > start");
        require(endTimeInSec >= cliffTimeInSec, "end > cliff");
        _;
    }

    modifier addressNotNull(address target) {
        require(target != address(0), "addressNotNull");
        _;
    }

    /// @dev Assigns a vesting token to the wallet.
    /// @param _vestingToken Token that will be vested.
    constructor(address _vestingToken) {
        vestingToken = DeltaTokenInterface(_vestingToken);
    }

     function batchRegisterVestingSchedule(
        address[] memory _addressesToRegister,
        address[] memory _depositors,
        uint[] memory _startTimesInSec,
        uint[] memory _cliffTimesInSec,
        uint[] memory _endTimesInSec,
        uint[] memory _totalAmounts
    )
        public
    {
        for (uint256 i = 0; i < _addressesToRegister.length; i++) {
            registerVestingSchedule(_addressesToRegister[i], _depositors[i], _startTimesInSec[i], _cliffTimesInSec[i], _endTimesInSec[i], _totalAmounts[i]);
        }
    }

    /// @dev Registers a vesting schedule to an address.
    /// @param _addressToRegister The address that is allowed to withdraw vested tokens for this schedule.
    /// @param _depositor Address that will be depositing vesting token.
    /// @param _startTimeInSec The time in seconds that vesting began.
    /// @param _cliffTimeInSec The time in seconds that tokens become withdrawable.
    /// @param _endTimeInSec The time in seconds that vesting ends.
    /// @param _totalAmount The total amount of tokens that the registered address can withdraw by the end of the vesting period.
    function registerVestingSchedule(
        address _addressToRegister,
        address _depositor,
        uint _startTimeInSec,
        uint _cliffTimeInSec,
        uint _endTimeInSec,
        uint _totalAmount
    )
        public
        onlyOwner
        addressNotNull(_depositor)
        vestingScheduleNotConfirmed(_addressToRegister)
        validVestingScheduleTimes(_startTimeInSec, _cliffTimeInSec, _endTimeInSec)
    {
        schedules[_addressToRegister] = VestingSchedule({
            startTimeInSec: _startTimeInSec,
            cliffTimeInSec: _cliffTimeInSec,
            endTimeInSec: _endTimeInSec,
            totalAmount: _totalAmount,
            totalAmountWithdrawn: 0,
            depositor: _depositor,
            isConfirmed: false
        });

        VestingScheduleRegistered(
            _addressToRegister,
            _depositor,
            _startTimeInSec,
            _cliffTimeInSec,
            _endTimeInSec,
            _totalAmount
        );
    }

    /// @dev Confirms a vesting schedule and deposits necessary tokens. Throws if deposit fails or schedules do not match.
    /// @param _startTimeInSec The time in seconds that vesting began.
    /// @param _cliffTimeInSec The time in seconds that tokens become withdrawable.
    /// @param _endTimeInSec The time in seconds that vesting ends.
    /// @param _totalAmount The total amount of tokens that the registered address can withdraw by the end of the vesting period.
    function confirmVestingSchedule(
        uint _startTimeInSec,
        uint _cliffTimeInSec,
        uint _endTimeInSec,
        uint _totalAmount
    )
        public
        addressRegistered(msg.sender)
        vestingScheduleNotConfirmed(msg.sender)
    {
        VestingSchedule storage vestingSchedule = schedules[msg.sender];

        require(vestingSchedule.startTimeInSec == _startTimeInSec, "start");
        require(vestingSchedule.cliffTimeInSec == _cliffTimeInSec, "cliff");
        require(vestingSchedule.endTimeInSec == _endTimeInSec, "end");
        require(vestingSchedule.totalAmount == _totalAmount, "amount");

        vestingSchedule.isConfirmed = true;
        require(vestingToken.transferFrom(vestingSchedule.depositor, address(this), _totalAmount));

        VestingScheduleConfirmed(
            msg.sender,
            vestingSchedule.depositor,
            _startTimeInSec,
            _cliffTimeInSec,
            _endTimeInSec,
            _totalAmount
        );
    }

    /// @dev Allows a registered address to withdraw tokens that have already been vested.
    function withdraw()
        public
        vestingScheduleConfirmed(msg.sender)
        pastCliffTime(msg.sender)
    {
        VestingSchedule storage vestingSchedule = schedules[msg.sender];

        uint totalAmountVested = getTotalAmountVested(vestingSchedule);
        uint amountWithdrawable = totalAmountVested.sub(vestingSchedule.totalAmountWithdrawn);
        vestingSchedule.totalAmountWithdrawn = totalAmountVested;

        if (amountWithdrawable > 0) {
            require(vestingToken.transfer(msg.sender, amountWithdrawable));
            Withdrawal(msg.sender, amountWithdrawable);
        }
    }

    /// @dev Allows contract owner to terminate a vesting schedule, transfering remaining vested tokens to the registered address and refunding owner with remaining tokens.
    /// @param _addressToEnd Address that is currently registered to the vesting schedule that will be closed.
    /// @param _addressToRefund Address that will receive unvested tokens.
    function endVesting(address _addressToEnd, address _addressToRefund)
        public
        onlyOwner
        vestingScheduleConfirmed(_addressToEnd)
        addressNotNull(_addressToRefund)
    {
        VestingSchedule storage vestingSchedule = schedules[_addressToEnd];

        uint amountWithdrawable = 0;
        uint amountRefundable = 0;

        if (block.timestamp < vestingSchedule.cliffTimeInSec) {
            amountRefundable = vestingSchedule.totalAmount;
        } else {
            uint totalAmountVested = getTotalAmountVested(vestingSchedule);
            amountWithdrawable = totalAmountVested.sub(vestingSchedule.totalAmountWithdrawn);
            amountRefundable = vestingSchedule.totalAmount.sub(totalAmountVested);
        }

        delete schedules[_addressToEnd];
        require(amountWithdrawable == 0 || vestingToken.transfer(_addressToEnd, amountWithdrawable));
        require(amountRefundable == 0 || vestingToken.transfer(_addressToRefund, amountRefundable));

        VestingEndedByOwner(_addressToEnd, amountWithdrawable, amountRefundable);
    }

    /// @dev Allows a registered address to request an address change.
    /// @param _newRegisteredAddress Desired address to update to.
    function requestAddressChange(address _newRegisteredAddress)
        public
        addressNotNull(_newRegisteredAddress)
        addressNotRegistered(_newRegisteredAddress)
        vestingScheduleConfirmed(msg.sender)
    {
        addressChangeRequests[msg.sender] = _newRegisteredAddress;
        AddressChangeRequested(msg.sender, _newRegisteredAddress);
    }

    /// @dev Confirm an address change and migrate vesting schedule to new address.
    /// @param _oldRegisteredAddress Current registered address.
    /// @param _newRegisteredAddress Address to migrate vesting schedule to.
    function confirmAddressChange(address _oldRegisteredAddress, address _newRegisteredAddress)
        public
        onlyOwner
        pendingAddressChangeRequest(_oldRegisteredAddress)
        addressNotRegistered(_newRegisteredAddress)
    {
        address newRegisteredAddress = addressChangeRequests[_oldRegisteredAddress];
        require(newRegisteredAddress == _newRegisteredAddress);    // prevents race condition

        VestingSchedule memory vestingSchedule = schedules[_oldRegisteredAddress];
        schedules[newRegisteredAddress] = vestingSchedule;

        delete schedules[_oldRegisteredAddress];
        delete addressChangeRequests[_oldRegisteredAddress];

        AddressChangeConfirmed(_oldRegisteredAddress, _newRegisteredAddress);
    }

    /// @dev Calculates the total tokens that have been vested for a vesting schedule, assuming the schedule is past the cliff.
    /// @param vestingSchedule Vesting schedule used to calculate vested tokens.
    /// @return Total tokens vested for a vesting schedule.
    function getTotalAmountVested(VestingSchedule memory vestingSchedule)
        internal
		view
        returns (uint)
    {
        if (block.timestamp >= vestingSchedule.endTimeInSec) return vestingSchedule.totalAmount;

        uint timeSinceStartInSec = block.timestamp.sub(vestingSchedule.startTimeInSec);
        uint totalVestingTimeInSec = vestingSchedule.endTimeInSec.sub(vestingSchedule.startTimeInSec);
        uint totalAmountVested = timeSinceStartInSec.mul(vestingSchedule.totalAmount).div(totalVestingTimeInSec);


        return totalAmountVested;
    }
}