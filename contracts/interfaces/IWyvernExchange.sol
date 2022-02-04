//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IWyvernExchange {
    function name ( ) external view returns ( string memory );
    function tokenTransferProxy ( ) external view returns ( address );
    function staticCall ( address target, bytes calldata, bytes memory extradata ) external view returns ( bool result );
    function changeMinimumMakerProtocolFee ( uint256 newMinimumMakerProtocolFee ) external;
    function changeMinimumTakerProtocolFee ( uint256 newMinimumTakerProtocolFee ) external;
    function guardedArrayReplace ( bytes memory array, bytes memory desired, bytes memory mask ) external pure returns ( bytes memory );
    function minimumTakerProtocolFee ( ) external view returns ( uint256 );
    function codename ( ) external view returns ( string memory );
    function testCopyAddress ( address addr ) external pure returns ( bytes memory );
    function testCopy ( bytes memory arrToCopy ) external pure returns ( bytes memory );
    function calculateCurrentPrice_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata ) external view returns ( uint256 );
    function changeProtocolFeeRecipient ( address newProtocolFeeRecipient ) external;
    function version ( ) external view returns ( string memory );
    function orderCalldataCanMatch ( bytes memory buyCalldata, bytes memory buyReplacementPattern, bytes memory sellCalldata, bytes memory sellReplacementPattern ) external pure returns ( bool );
    function validateOrder_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata, uint8 v, bytes32 r, bytes32 s ) external view returns ( bool );
    function calculateFinalPrice ( uint8 side, uint8 saleKind, uint256 basePrice, uint256 extra, uint256 listingTime, uint256 expirationTime ) external view returns ( uint256 );
    function protocolFeeRecipient ( ) external view returns ( address );
    function renounceOwnership ( ) external;
    function hashOrder_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata ) external pure returns ( bytes32 );
    function ordersCanMatch_ ( address[14] memory addrs, uint256[18] memory uints, uint8[8] memory feeMethodsSidesKindsHowToCalls, bytes memory calldataBuy, bytes memory calldataSell, bytes memory replacementPatternBuy, bytes memory replacementPatternSell, bytes memory staticExtradataBuy, bytes memory staticExtradataSell ) external view returns ( bool );
    function approveOrder_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata, bool orderbookInclusionDesired ) external;
    function registry ( ) external view returns ( address );
    function minimumMakerProtocolFee ( ) external view returns ( uint256 );
    function hashToSign_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata ) external pure returns ( bytes32 );
    function cancelledOrFinalized ( bytes32 ) external view returns ( bool );
    function owner ( ) external view returns ( address );
    function exchangeToken ( ) external view returns ( address );
    function cancelOrder_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata, uint8 v, bytes32 r, bytes32 s ) external;
    function atomicMatch_ ( address[14] memory addrs, uint256[18] memory uints, uint8[8] memory feeMethodsSidesKindsHowToCalls, bytes calldata calldataBuy, bytes calldata calldataSell, bytes memory replacementPatternBuy, bytes memory replacementPatternSell, bytes memory staticExtradataBuy, bytes memory staticExtradataSell, uint8[2] memory vs, bytes32[5] memory rssMetadata ) external payable;
    function validateOrderParameters_ ( address[7] memory addrs, uint256[9] memory uints, uint8 feeMethod, uint8 side, uint8 saleKind, uint8 howToCall, bytes calldata, bytes memory replacementPattern, bytes memory staticExtradata ) external view returns ( bool );
    function INVERSE_BASIS_POINT ( ) external view returns ( uint256 );
    function calculateMatchPrice_ ( address[14] memory addrs, uint256[18] memory uints, uint8[8] memory feeMethodsSidesKindsHowToCalls, bytes memory calldataBuy, bytes memory calldataSell, bytes memory replacementPatternBuy, bytes memory replacementPatternSell, bytes memory staticExtradataBuy, bytes memory staticExtradataSell ) external view returns ( uint256 );
    function approvedOrders ( bytes32 ) external view returns ( bool );
    function transferOwnership ( address newOwner ) external;
}
