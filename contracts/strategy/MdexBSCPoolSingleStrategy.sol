// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../mdex/IMdexFactory.sol";
import "../mdex/IMdexRouter.sol";
import "../mdex/IMdexPair.sol";
import "../controller/IController.sol";
import "../strategy/IStrategy.sol";
import "./BaseStrategy.sol";
import "../rewardPool/IBSCPool.sol";
import "./MdexBSCPoolBaseStrategy.sol";

contract MdexBSCPoolSingleStrategy is MdexBSCPoolBaseStrategy {
    using Address for address;
    using SafeMath for uint;

    address[] public mdexRoutes;
    //use the route to calculate price
    address[] public mdexPriceCalcRoutes;

    constructor(
        IVault _vault,
        IController _controller,
        IERC20 _capital,
        address _swapRouter,
        IERC20 _rewardToken,
        IBSCPool _pool,
        uint256 _poolID,
        ISwapMining _swapMining,
        uint256 _profitFee
    )MdexBSCPoolBaseStrategy(_vault, _controller, _capital, _swapRouter, _rewardToken, _pool, _poolID, _swapMining, _profitFee) public {
    }


    //mostly called from vault and public
    function circulate() override permitted public {
        // pool -> reward
        getPoolReward();
        // reward token -> capital
        compound();
        //capital -> pool
        invest();
    }

    // reward -> capital
    function compound() override internal {
        uint256 beforeCapitalBalance = balanceOfStrategy();

        uint256 reward = rewardToken.balanceOf(address(this));
        if (reward > 0 && capital_ != rewardToken) {
            // need to do swap from reward token to capital token
            rewardToken.safeApprove(swapRouter, reward);

            IMdexRouter(swapRouter).swapExactTokensForTokens(
                reward,
                1,
                mdexRoutes,
                address(this),
                block.timestamp + 100
            );

        }
        uint256 afterCapitalBalance = balanceOfStrategy();
        if (afterCapitalBalance > 0) {
            settleProfit(beforeCapitalBalance, afterCapitalBalance);
        }
    }


    function setMdexRoutes(address[] calldata _mdexRoutes, address[] calldata _mdexPriceCalcRoutes) onlyOwner external {
        require(_mdexRoutes[0] == address(rewardToken), "mdexRoutes[0] == address(rewardToken)");
        require(_mdexRoutes[_mdexRoutes.length.sub(1)] == address(capital_), "mdexRoutes[mdexRoutes.length.sub(1)] == address(capital_)");
        mdexRoutes = _mdexRoutes;

        //====================================
        //capital route -> usdt or usdt-like
        require(_mdexPriceCalcRoutes.length >= 1, "_mdexPriceCalcRoutes.length >= 1");
        require(_mdexPriceCalcRoutes[0] == address(capital_), "_mdexPriceCalcRoutes[0] == capital_");
        mdexPriceCalcRoutes = _mdexPriceCalcRoutes;
    }

    // if route.length =1, it means capital is the usdt or busd
    // if route.length =1, usdt/capital(usdt) -> 1
    // if route.length >1, capital(sushi),ht,usdt,  ht/sushi * usdt/ht
    // if route.length >1, capital(sushi),ht,usdt,  sushi(lp0)/lp * ht/sushi * usdt/ht -> usdt/lp
    function getCapitalPrice() external view override returns (uint256){
        require(mdexPriceCalcRoutes.length > 0, "mdexPriceCalcRoutes.length>0");
        uint256 baseDecimal = 1e18;
        uint256 price = baseDecimal;

        if (mdexPriceCalcRoutes.length == 1) {
            //the capital is usdt or busd, no need for route
            return price;
        }

        //lp0 is not usdt or busd

        IMdexFactory mdexFactory = IMdexFactory(IMdexRouter(swapRouter).factory());
        //length >=2
        for (uint256 i = 0; i < mdexPriceCalcRoutes.length.sub(1); i++) {
            address token0 = mdexPriceCalcRoutes[i];
            address token1 = mdexPriceCalcRoutes[i + 1];

            address mdexPair = mdexFactory.getPair(token0, token1);
            if (mdexPair == address(0)) {
                revert("error routes");
            }
            (uint256 reserve0,uint256 reserve1,) = IMdexPair(mdexPair).getReserves();
            if (IMdexPair(mdexPair).token0() == token1) {
                uint256 temp = reserve0;
                reserve0 = reserve1;
                reserve1 = temp;
            }
            // token1 per token0
            price = price.mul(reserve1).div(reserve0);
        }
        return price;
    }

}
