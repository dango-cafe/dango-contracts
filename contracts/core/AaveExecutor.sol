//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import { 
    IERC20,
    IWETH,
    ILendingPool,
    ITokenIncentives,
    IProtocolDataProvider
} from "../utils/Interfaces.sol";
import { SafeERC20 } from "../utils/Libraries.sol";

contract AaveExecutor {
    using SafeERC20 for IERC20;

    event Deposit(
        address indexed user,
        address indexed collateral,
        uint256 amt
    );

    event Withdraw(
        address indexed user,
        address indexed to,
        address indexed collateral,
        uint256 amt
    );

    event Borrow(
        address indexed user,
        address indexed to,
        address indexed debt,
        uint256 amt,
        uint256 rateMode
    );

    event Repay(
        address indexed user,
        address indexed debt,
        uint256 amt,
        uint256 rateMode
    );

    event ClaimRewards(
        address indexed user,
        address indexed to,
        uint256 amt
    );

    event SetReserveAsCollateral(
        address indexed user,
        address indexed collateral,
        bool indexed useAs
    );

    event SwapBorrowRateMode(
        address indexed user,
        address indexed debt,
        uint256 indexed rateMode
    );

    ILendingPool public immutable lendingPool;
    IProtocolDataProvider public immutable dataProvider;
    ITokenIncentives public immutable incentives;
    address internal constant ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant wethAddr = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    constructor (address _lendingPool, address _dataProvider, address _incentives) {
        lendingPool = ILendingPool(_lendingPool);
        dataProvider = IProtocolDataProvider(_dataProvider);
        incentives = ITokenIncentives(_incentives);
    }

    function deposit(address asset, uint256 amt) external payable {
        IERC20 collateral = IERC20(asset);

        if (asset == ethAddr) {
            require(msg.value == amt, "invalid-amount");
            IWETH(wethAddr).deposit{value: amt}();
            collateral = IERC20(wethAddr);
        } else {
            collateral.safeTransferFrom(msg.sender, address(this), amt);
        }

        collateral.safeApprove(address(lendingPool), amt);
        lendingPool.deposit(address(collateral), amt, address(this), 0);

        emit Deposit(address(this), asset, amt);
    }

    function withdraw(address asset, address to, uint256 amt) external payable {
        IERC20 collateral = IERC20(asset);
        uint256 finalAmt = amt;
        bool isEth = asset == ethAddr;

        if (isEth) {
            collateral = IERC20(wethAddr);
        }

        if (amt == type(uint256).max) {
            (finalAmt, , , , , , , ,) = dataProvider.getUserReserveData(address(collateral), address(this));
        }

        lendingPool.withdraw(address(this), finalAmt, address(this));

        if (isEth) {
            collateral.safeApprove(wethAddr, finalAmt);
            IWETH(wethAddr).withdraw(finalAmt);
            payable(to).transfer(finalAmt);
        } else {
            collateral.safeTransfer(to, finalAmt);
        }

        emit Withdraw(address(this), to, asset, finalAmt);
    }

    function borrow(address asset, address to, uint256 amt, uint256 rateMode) external payable {
        require(rateMode == 1 || rateMode == 2, "invalid-rate-mode");
        IERC20 debt = IERC20(asset);
        bool isEth = asset == ethAddr;

        if (isEth) {
            debt = IERC20(wethAddr);
        }

        lendingPool.borrow(address(debt), amt, rateMode, 0, address(this));

        if (isEth) {
            debt.safeApprove(wethAddr, amt);
            IWETH(wethAddr).withdraw(amt);
            payable(to).transfer(amt);
        } else {
            debt.safeTransfer(to, amt);
        }

        emit Borrow(address(this), to, asset, amt, rateMode);
    }

    function repay(address asset, uint256 amt, uint256 rateMode) external payable {
        require(rateMode == 1 || rateMode == 2, "invalid-rate-mode");
        uint256 finalAmt = amt;
        IERC20 debt = IERC20(asset);

        if (asset == ethAddr) {
            require(msg.value == amt, "invalid-amount");
            IWETH(wethAddr).deposit{value: amt}();
            debt = IERC20(wethAddr);
        } else {
            if (amt == type(uint256).max) {
                (,uint stableDebt, uint256 varDebt,,,,,,) = dataProvider.getUserReserveData(address(debt), address(this));
                finalAmt = rateMode == 2 ? varDebt : stableDebt;
            }
            debt.safeTransferFrom(msg.sender, address(this), finalAmt);
        }

        debt.approve(address(lendingPool), finalAmt);
        lendingPool.repay(address(debt), amt, rateMode, address(this));

        emit Repay(address(this), asset, finalAmt, rateMode);
    }

    function claimRewards(address[] calldata assets, address to) external payable {
        uint256 rewards = incentives.getRewardsBalance(assets, address(this));
        incentives.claimRewards(assets, rewards, to);

        emit ClaimRewards(address(this), to, rewards);
    }

    function setReservesAsCollateral(address asset, bool useAsCollateral) external payable {
        address collateral = asset == ethAddr ? wethAddr : asset;
        lendingPool.setUserUseReserveAsCollateral(collateral, useAsCollateral);

        emit SetReserveAsCollateral(address(this), asset, useAsCollateral);
    }

    function swapBorrowRateMode(address asset, uint256 rateMode) external payable {
        require(rateMode == 1 || rateMode == 2, "invalid-rate-mode");
        address debt = asset == ethAddr ? wethAddr : asset;

        lendingPool.swapBorrowRateMode(debt, rateMode);

        emit SwapBorrowRateMode(address(this), debt, rateMode);
    }
}