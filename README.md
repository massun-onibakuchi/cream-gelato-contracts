# Cream Gelato Liquidation Protection
Automated Health Factor Maintenance Proof of Concept

Cream Fi and Gelato Network integration

see Notes section

## Concept

CreamFi users can specify their Minimum Health Factor and their Wanted Health Factor. Once a user’s Health Factor on CreamFi drops below their specified minimum threshold, Gelato will rebalance the user’s debt position on Cream, to attain the user’s specified Wanted Health Factor again. The bots achieve this on behalf of the user by swapping some of the user’s collateral for debt token and then repaying some of that debt. The bots swap the user’s collateral on Uniswap V2. This repo use Gelato PokeMe for autometed task. 

This liquidation protection system is inspired by [Cono Finance](https://medium.com/gelato-network/cono-finance-is-here-to-protect-your-aave-debt-positions-wagmi-4ed1b57f8ed5)

### Notes
Currently, Cream is the same flash loan design as aave v1. This type of flash loan verifies that the amount of tokens the protocol has before and after the flash loan is constant (+fee). Aave v2 verifies that users can return the tokens they borrowed with flash loans (+fee). Therefore,in v1 design it is not possible to redeem cToken(crToken,aToken) in the flash loan callback function. 

*In this repo, we use a mock crToken that has the same flash loan design as Aave v2.* 

See the links below for detailed differences

[Aave Flash loans guide](https://docs.aave.com/developers/guides/flash-loans)

[Aave v1 Flash loan](https://github.com/aave/aave-protocol/blob/4b4545fb583fd4f400507b10f3c3114f45b8a037/contracts/lendingpool/LendingPool.sol#L888-L891)

[Aave v2 Flash loan](https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol#L537)

## Usage
## Setup
To install dependencies, run

`yarn`

### Complipe
`yarn compile`

### Test
`yarn test`

## Link
[Cream fi Gitcoin #2 Loan saver](https://gitcoin.co/issue/CreamFi/Open-Defi/2/100026342)

[Cream fi Doc](https://docs.cream.finance)

[GitHub:Gelato PokeMe](https://github.com/gelatodigital/poke-me/)

[Cono finance](https://www.cono.finance/assets)

[Medium:Gelato Receives Grant From Aave to Protect Users From Liquidation](https://medium.com/gelato-network/gelato-receives-grant-from-aave-to-protect-users-from-liquidation-a265c3256f5d)

[Cono Finance Is Here To Protect Your Aave Debt Positions — WAGMI!](https://medium.com/gelato-network/cono-finance-is-here-to-protect-your-aave-debt-positions-wagmi-4ed1b57f8ed5)