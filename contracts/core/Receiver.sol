//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { FlashLoanReceiverBase } from "../utils/FlashLoanReceiverBase.sol";
import { 
    IERC20,
    IProxy,
    ILendingPool,
    ILendingPoolAddressesProvider
} from "../utils/Interfaces.sol";
import { SafeMath, SafeERC20, DataTypes } from "../utils/Libraries.sol";

contract DangoReceiver is FlashLoanReceiverBase, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address internal constant ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant wethAddr = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address public immutable executor;

    mapping (address => bool) public whitelist;

    constructor(ILendingPoolAddressesProvider _addressProvider, address _executor) FlashLoanReceiverBase(_addressProvider) {
        executor = _executor;
    }

    function addAccess(address trader) public onlyOwner {
        require(!whitelist[trader], "already-whitelisted");

        whitelist[trader] = true;
    }

    function removeAccess(address trader) public onlyOwner {
        require(whitelist[trader], "not-whitelisted");

        whitelist[trader] = false;
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
        collateral.safeTransferFrom(msg.sender, address(this), data.collateralAmount);

        if (data.collateralAsset != data.debtAsset) {
            require(whitelist[data.tradeTarget], "not-whitelisted");
            IERC20(data.debtAsset).safeApprove(data.tradeTarget, data.debtAmount);
            (bool success, ) = address(data.tradeTarget).call(data.tradeData);
            if (!success) revert("trade-failed");
        }

        require(collateral.balanceOf(address(this)) > data.collateralAmount, "trade-failed");

        uint256 totalAmount = collateral.balanceOf(address(this));
        collateral.safeApprove(address(LENDING_POOL), totalAmount);
        LENDING_POOL.deposit(address(collateral), totalAmount, initiator, 0);
    }

    function deleverage(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        DataTypes.LeverageData memory data
    ) internal {
        require(data.collateralAsset == asset, "data-mismatch");

        IERC20 debtAsset = IERC20(data.debtAsset);
        IERC20 collateral = IERC20(data.collateralAsset);

        if (asset != data.debtAsset) {
            require(whitelist[data.tradeTarget], "not-whitelisted");
            IERC20(asset).safeApprove(data.tradeTarget, amount);
            (bool success, ) = address(data.tradeTarget).call(data.tradeData);
            if (!success) revert("trade-failed");
        }

        require(debtAsset.balanceOf(address(this)) >= data.debtAmount, "trade-failed");

        debtAsset.safeApprove(address(LENDING_POOL), data.debtAmount);
        LENDING_POOL.repay(data.debtAsset, data.debtAmount, data.debtMode, initiator);

        uint256 amtOwed = amount.add(premium);

        uint256 initialBal = collateral.balanceOf(address(this));
        IProxy(initiator).execute(executor, abi.encodeWithSignature("withdrawAndReturn(address,uint256)", data.collateralAsset, amtOwed));
        uint256 finalBal = collateral.balanceOf(address(this));
        require(finalBal.sub(initialBal) == amtOwed, "withdraw-failed");

        collateral.safeApprove(address(LENDING_POOL), amtOwed);
    }
}