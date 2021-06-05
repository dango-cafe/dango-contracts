//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { FlashLoanReceiverBase } from "../utils/FlashLoanReceiverBase.sol";
import { 
    IERC20,
    IProxy,
    ILendingPool,
    IProtocolDataProvider,
    ILendingPoolAddressesProvider
} from "../utils/Interfaces.sol";
import { SafeMath, SafeERC20, DataTypes } from "../utils/Libraries.sol";

contract DangoReceiver is FlashLoanReceiverBase, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Leverage(
        address indexed user,
        address indexed collateral,
        address indexed debt,
        uint256 amt,
        uint256 totalAmt,
        uint256 debtAmt
    );

    event Deleverage(
        address indexed user,
        address indexed collateral,
        address indexed debt,
        uint256 amt,
        uint256 totalAmt,
        uint256 debtAmt
    );

    uint256 constant WAD = 10 ** 18;

    address internal constant ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant wethAddr = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address public immutable executor;
    IProtocolDataProvider public immutable dataProvider;

    mapping (address => bool) public whitelist;

    constructor(
        ILendingPoolAddressesProvider _addressProvider,
        address _executor,
        address _dataProvider
    ) FlashLoanReceiverBase(_addressProvider) {
        executor = _executor;
        dataProvider = IProtocolDataProvider(_dataProvider);
    }

    function addAccess(address trader) public onlyOwner {
        require(!whitelist[trader], "already-whitelisted");

        whitelist[trader] = true;
    }

    function removeAccess(address trader) public onlyOwner {
        require(whitelist[trader], "not-whitelisted");

        whitelist[trader] = false;
    }

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = SafeMath.add(SafeMath.mul(x, y), WAD / 2) / WAD;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        DataTypes.LeverageData memory data = abi.decode(params, (DataTypes.LeverageData));

        if (data.opMode == 1) {
            leverage(assets[0], amounts[0], initiator, data);
        } else {
            deleverage(assets[0], amounts[0], premiums[0], initiator, data);
        }

        return true;
    }

    function leverage(
        address asset,
        uint256 amount,
        address initiator,
        DataTypes.LeverageData memory data
    ) internal {
        require(data.debtAsset == asset, "data-mismatch");
        require(data.debtAmount == amount, "data-mismatch");

        IERC20 collateral = IERC20(data.collateralAsset);
        collateral.safeTransferFrom(initiator, address(this), data.collateralAmount);

        if (data.collateralAsset != data.debtAsset) {
            require(whitelist[data.tradeTarget], "not-whitelisted");
            uint256 initBal = collateral.balanceOf(address(this));

            IERC20(data.debtAsset).safeApprove(address(data.tradeTarget), data.debtAmount);
            (bool success, ) = data.tradeTarget.call(data.tradeData);
            if (!success) revert("trade-failed");

            uint256 finalBal = collateral.balanceOf(address(this));
            uint256 received = finalBal.sub(initBal);
            require(received > 0, "no-trade-happened");
        }

        uint256 totalAmount = collateral.balanceOf(address(this));

        require(totalAmount > data.collateralAmount, "trade-failed");

        collateral.safeApprove(address(LENDING_POOL), totalAmount);
        LENDING_POOL.deposit(address(collateral), totalAmount, initiator, 0);

        emit Leverage(initiator, data.collateralAsset, data.debtAsset, data.collateralAmount, totalAmount, data.debtAmount);
    }

    function deleverage(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        DataTypes.LeverageData memory data
    ) internal {
        require(data.collateralAsset == asset, "data-mismatch");

        IERC20 collateral = IERC20(data.collateralAsset);

        (uint256 totalAmt,,,,,,,,) = dataProvider.getUserReserveData(data.collateralAsset, initiator);

        if (asset != data.debtAsset) {
            require(whitelist[data.tradeTarget], "not-whitelisted");
            uint256 initBal = IERC20(data.debtAsset).balanceOf(address(this));

            IERC20(asset).safeApprove(address(data.tradeTarget), amount);
            (bool success, ) = data.tradeTarget.call(data.tradeData);
            if (!success) revert("trade-failed");

            uint256 finalDebtBal = IERC20(data.debtAsset).balanceOf(address(this));
            uint256 received = finalDebtBal.sub(initBal);
            require(received > 0, "no-trade-happened");
        }

        uint256 finalDebtRepaying;

        {
            uint256 debtAssetBal = IERC20(data.debtAsset).balanceOf(address(this));
            (,uint stableDebt, uint256 varDebt,,,,,,) = dataProvider.getUserReserveData(data.debtAsset, initiator);
            uint256 maxDebt = data.debtMode == 2 ? varDebt : stableDebt;
            bool isOverpay = debtAssetBal >= maxDebt;
            uint256 debtRepaying = isOverpay ? type(uint256).max : debtAssetBal;
            require(debtRepaying >= data.debtAmount, "trade-failed");
            finalDebtRepaying = isOverpay ? maxDebt : debtAssetBal;

            IERC20(data.debtAsset).safeApprove(address(LENDING_POOL), finalDebtRepaying);
            LENDING_POOL.repay(data.debtAsset, finalDebtRepaying, data.debtMode, initiator);
            if (isOverpay) {
                address owner = IProxy(initiator).owner();
                IERC20(data.debtAsset).safeTransfer(owner, debtAssetBal.sub(maxDebt));
            }
        }

        uint256 amtOwed = amount.add(premium);

        uint256 initialBal = collateral.balanceOf(address(this));
        IProxy(initiator).execute(executor, abi.encodeWithSignature("withdrawAndReturn(address,uint256)", data.collateralAsset, amtOwed));
        uint256 finalBal = collateral.balanceOf(address(this));
        require(finalBal.sub(initialBal) == amtOwed, "withdraw-failed");

        collateral.safeApprove(address(LENDING_POOL), amtOwed);

        emit Deleverage(initiator, asset, data.debtAsset, amtOwed, totalAmt, finalDebtRepaying);
    }
}