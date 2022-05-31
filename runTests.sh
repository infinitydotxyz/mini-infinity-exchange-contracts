#! /bin/sh

# helps in reading stdout better
printSeparator() {
    echo '======================================= Test Complete ========================================='
    echo '+++++++++++++++++++++++++++++++++++++ Running next test +++++++++++++++++++++++++++++++++++++++'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
    echo '***********************************************************************************************'
}

echo 'Running all tests...'
npx hardhat test --grep Exchange_Cancel
printSeparator

npx hardhat test --grep Exchange_Creator
printSeparator

npx hardhat test --grep Exchange_ETH_Creator_Fee_Maker_Sell_Taker_Buy
printSeparator

npx hardhat test --grep Exchange_Invalid
printSeparator

npx hardhat test --grep Exchange_Maker_Buy
printSeparator

npx hardhat test --grep Exchange_Maker_Sell
printSeparator

npx hardhat test --grep Exchange_ETH_Maker_Sell_Taker_Buy
printSeparator

npx hardhat test --grep Exchange_Match
printSeparator

npx hardhat test --grep Exchange_One_To_Many
printSeparator

npx hardhat test --grep Exchange_Varying
printSeparator

echo 'All tests complete!'