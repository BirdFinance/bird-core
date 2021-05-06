// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../mdex/IMdexFactory.sol";
import "../mdex/IMdexRouter.sol";
import "../mdex/IMdexPair.sol";
import "../vaults/IVault.sol";
import "../strategy/IStrategy.sol";
import "../rewardPool/IBSCPool.sol";
import "./MdexBSCPoolBaseStrategy.sol";


contract MdexBSCPoolLPStrategy is MdexBSCPoolBaseStrategy {
    using SafeMath for uint;

    address[] public mdexRoutesRewardToLp0;
    address[] public mdexRoutesLp0ToLp1;

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
    ) MdexBSCPoolBaseStrategy(_vault, _controller, _capital, _swapRouter, _rewardToken, _pool, _poolID, _swapMining, _profitFee) public {
    }

    function circulate() external override permitted {
        // pool -> reward
        getPoolReward();
        // reward token -> capital
        compound();
        //capital -> pool
        invest();
    }

    // reward -> capital
    function compound() override internal {

        uint256 reward = rewardToken.balanceOf(address(this));

        IERC20 lpToken0 = IERC20(IMdexPair(address(capital_)).token0());
        IERC20 lpToken1 = IERC20(IMdexPair(address(capital_)).token1());

        uint256 beforeBalance = balanceOfStrategy();

        if (reward > 0 // we have tokens to swap
        && mdexRoutesRewardToLp0.length > 1 // and we have a route to do the swap
            && mdexRoutesLp0ToLp1.length > 1 // and we have a route to do the swap
        ) {
            if (rewardToken != lpToken0) {
                //mdx<>usdt -> mdx

                rewardToken.approve(swapRouter, 0);
                rewardToken.approve(swapRouter, reward);

                //reward -> lp0
                IMdexRouter(swapRouter).swapExactTokensForTokens(
                    reward, //all
                    1, //accept all slippage, but not burn
                    mdexRoutesRewardToLp0,
                    address(this),
                    block.timestamp + 100
                );
            }

            uint256 lpToken0Amount = lpToken0.balanceOf(address(this));
            lpToken0.approve(swapRouter, 0);
            lpToken0.approve(swapRouter, lpToken0Amount);

            //half of lp0, goes into lp1
            lpToken0Amount = lpToken0Amount.div(2);
            //don't care the remainder 1
            IMdexRouter(swapRouter).swapExactTokensForTokens(
                lpToken0Amount,
                1,
                mdexRoutesLp0ToLp1,
                address(this),
                block.timestamp + 100
            );
            uint256 lpToken1Amount = lpToken1.balanceOf(address(this));

            lpToken1.approve(swapRouter, 0);
            lpToken1.approve(swapRouter, lpToken1Amount);

            //add lp0 and lp1 into liquidity
            uint256 liquidity;
            (,, liquidity) = IMdexRouter(swapRouter).addLiquidity(
                address(lpToken0),
                address(lpToken1),
                lpToken0Amount,
                lpToken1Amount,
                1, // we are willing to take whatever the pair gives us
                1, // we are willing to take whatever the pair gives us
                address(this),
                block.timestamp + 100
            );
        }
        uint256 afterBalance = balanceOfStrategy();
        if (afterBalance > 0) {
            settleProfit(beforeBalance, afterBalance);
        }
    }

    function setMdexRoutes(address[] calldata _mdexRoutesRewardToLp0, address[] calldata _mdexRoutesLp0ToLp1, address[] calldata _mdexPriceCalcRoutes) onlyOwner external {
        address lpToken0 = IMdexPair(address(capital_)).token0();
        address lpToken1 = IMdexPair(address(capital_)).token1();

        require(_mdexRoutesRewardToLp0[0] == address(rewardToken), "_mdexRoutesRewardToLp0[0] == address(rewardToken)");
        require(_mdexRoutesRewardToLp0[_mdexRoutesRewardToLp0.length.sub(1)] == lpToken0, "_mdexRoutesRewardToLp0[_mdexRoutesRewardToLp0.length.sub(1)] == lpToken0");

        require(_mdexRoutesLp0ToLp1[0] == lpToken0, "_mdexRoutesLp0ToLp1[0] == lpToken0");
        require(_mdexRoutesLp0ToLp1[_mdexRoutesLp0ToLp1.length.sub(1)] == lpToken1, "_mdexRoutesLp0ToLp1[_mdexRoutesLp0ToLp1.length.sub(1)] == lpToken1");


        mdexRoutesRewardToLp0 = _mdexRoutesRewardToLp0;
        mdexRoutesLp0ToLp1 = _mdexRoutesLp0ToLp1;

        //====================================
        //lp0 -> usdt or usdt-like
        require(_mdexPriceCalcRoutes.length >= 1, "_mdexPriceCalcRoutes.length >= 1");
        require(_mdexPriceCalcRoutes[0] == lpToken0, "_mdexPriceCalcRoutes[0] == lpToken0");
        mdexPriceCalcRoutes = _mdexPriceCalcRoutes;
    }

    // capitial price in usdt/busd
    // if route.length =1, it means lp0 is the usdt or busd
    // if route.length =1, usdt/lp -> usdt/lp
    // if route.length >1, lp0(sushi),ht,usdt,  ht/sushi * usdt/ht
    // if route.length >1, lp0(sushi),ht,usdt,  sushi(lp0)/lp * ht/sushi * usdt/ht -> usdt/lp
    function getCapitalPrice() external view override returns (uint256 price18){
        require(mdexPriceCalcRoutes.length > 0, "mdexPriceCalcRoutes.length>0");
        price18 = baseDecimal;


        uint256 totalLp = IMdexPair(address(capital_)).totalSupply();
        (uint256 totalLpToken0,,) = IMdexPair(address(capital_)).getReserves();

        //how much token0 per lp
        //mul 2 is for pair :)
        price18 = price18.mul(totalLpToken0).div(totalLp).mul(2);

        if (mdexPriceCalcRoutes.length == 1) {
            //the token0 is usdt or busd, no need for route
            return price18;
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
            //assume token0 is the denominator(per token0)
            if (IMdexPair(mdexPair).token0() == token1) {
                uint256 temp = reserve0;
                reserve0 = reserve1;
                reserve1 = temp;
            }
            // token1 per token0
            price18 = price18.mul(reserve1).div(reserve0);
        }
        return price18;
    }


}
