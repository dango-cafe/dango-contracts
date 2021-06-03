//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import { 
    IERC20,
    IWETH,
    IProxy,
    IDebtToken,
    ILendingPool,
    IProtocolDataProvider,
    ILendingPoolAddressesProvider
} from "../utils/Interfaces.sol";
import { SafeMath, SafeERC20, DataTypes } from "../utils/Libraries.sol";

contract DangoExecutor {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable receiver;
    ILendingPool public immutable lendingPool;
    IProtocolDataProvider public immutable dataProvider;
    address internal constant ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant wethAddr = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    constructor(address _receiver, address _provider, address _dataProvider) {
        receiver = _receiver;
        address _lendingPool = ILendingPoolAddressesProvider(_provider).getLendingPool();
        lendingPool = ILendingPool(_lendingPool);
        dataProvider = IProtocolDataProvider(_dataProvider);
    }

    function leverage(DataTypes.LeverageData memory data) external payable {
        require(data.opMode == 1, "wrong-method");
        IERC20 collateral;
        IProxy proxy = IProxy(address(this));

        if (data.collateralAsset == ethAddr) {
            require(msg.value == data.collateralAmount, "invalid-amount");
            IWETH(wethAddr).deposit{value: data.collateralAmount}();
            collateral = IERC20(wethAddr);
        } else {
            collateral = IERC20(data.collateralAsset);
            collateral.safeTransferFrom(msg.sender, address(this), data.collateralAmount);
        }

        collateral.safeApprove(receiver, data.collateralAmount);

        (, address stableDebtToken, address variableDebtToken) = dataProvider.getReserveTokensAddresses(data.debtAsset);

        uint256 premium = data.debtAmount.mul(9).div(10000);
        uint256 debtWithPremium = data.debtAmount.add(premium);

        if (data.debtMode == 2) {
            IDebtToken(variableDebtToken).approveDelegation(receiver, debtWithPremium);
        } else {
            IDebtToken(stableDebtToken).approveDelegation(receiver, debtWithPremium);
        }

        data.collateralAsset = address(collateral);

        proxy.addAuth(receiver);

        address[] memory assets = new address[](1);
        assets[0] = address(data.debtAsset);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = data.debtAmount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = uint256(data.debtMode);

        bytes memory params = abi.encode(data);
        uint16 referralCode = 0;

        lendingPool.flashLoan(
            receiver,
            assets,
            amounts,
            modes,
            address(this),
            params,
            referralCode
        );

        proxy.removeAuth(receiver);
    }

    function deleverage(DataTypes.LeverageData memory data, uint256 flashAmt) external payable {
        require(data.opMode == 2, "wrong-method");

        IProxy proxy = IProxy(address(this));

        (address aToken,,) = dataProvider.getReserveTokensAddresses(data.collateralAsset);
        uint256 aTokenBal = IERC20(aToken).balanceOf(address(this));
        require(aTokenBal > 0, "no-collateral");
        require(flashAmt < aTokenBal, "insufficient-collateral");
        if (data.collateralAmount > aTokenBal) {
            data.collateralAmount = aTokenBal;
        }

        (, address stableDebtToken, address variableDebtToken) = dataProvider.getReserveTokensAddresses(data.debtAsset);
        address debtToken = data.debtMode == 2 ? variableDebtToken : stableDebtToken;
        uint256 maxDebt = IERC20(debtToken).balanceOf(address(this));
        require(maxDebt > 0, "no-debt");
        if (data.debtAmount > maxDebt) {
            data.debtAmount = maxDebt;
        }

        proxy.addAuth(receiver);

        address[] memory assets = new address[](1);
        assets[0] = address(data.collateralAsset);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashAmt;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        bytes memory params = abi.encode(data);
        uint16 referralCode = 0;

        lendingPool.flashLoan(
            receiver,
            assets,
            amounts,
            modes,
            address(this),
            params,
            referralCode
        );

        proxy.removeAuth(receiver);
    }

    function withdrawAndReturn(address asset, uint256 amount) external payable {
        lendingPool.withdraw(asset, amount, receiver);
    }
}